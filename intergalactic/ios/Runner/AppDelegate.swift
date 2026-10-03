import Flutter
import AVFoundation
import Intents
import AVKit
import CryptoKit
import LocalAuthentication
import MediaPlayer
import Photos
import Security
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appGroupStorageChannelName = "chat.intergalactic.app/app_group_storage"
  private let appIconChannelName = "chat.intergalactic.app/app_icon"
  private let backgroundAssertionChannelName = "chat.intergalactic.app/background_assertion"
  private let biometricsChannelName = "chat.intergalactic.app/biometrics"
  private let callAudioChannelName = "chat.intergalactic.app/call_audio"
  private let cameraMediaPickerChannelName = "chat.intergalactic.app/ios_camera_media_picker"
  private let inboundShareChannelName = "chat.intergalactic.app/inbound_share"
  private let inboundShareAppGroup = "group.chat.intergalactic.app"
  private let inboundShareStagingDirectory = "inbound-share"
  /// How long a handed-out session stays reserved before another pull may retry
  /// it. Long enough for a channel round-trip and a manifest read; short enough
  /// that a share lost to a crash comes back on the next resume.
  private let inboundShareReservationTimeout: TimeInterval = 300
  /// Sessions the user never returned for are swept at this age.
  private let inboundShareSessionMaxAge: TimeInterval = 7 * 24 * 60 * 60
  /// Every store operation runs here rather than on the platform thread.
  ///
  /// `reserveNext` enumerates the App Group directory, stats every entry, and
  /// can recursively delete an aged session holding hundreds of megabytes;
  /// `reject` deletes one outright. `FlutterMethodChannel` handlers run on the
  /// platform (main) thread, and Dart drains up to twenty sessions in a loop at
  /// startup and again on every resume, so leaving this synchronous stalls
  /// launch and resume on file I/O.
  ///
  /// Serial on purpose: it keeps the ordering the main-thread version had, so
  /// moving off the main thread does not by itself let two drains interleave.
  private let inboundShareQueue = DispatchQueue(
    label: "chat.intergalactic.app.inbound-share",
    qos: .userInitiated
  )
  private let localMediaControlsChannelName = "chat.intergalactic.app/local_media_controls"
  private let mediaSaverChannelName = "chat.intergalactic.app/media_saver"
  private let mediaShareChannelName = "chat.intergalactic.app/media_share"
  private let mobileCallBackgroundChannelName = "chat.intergalactic.app/mobile_call_background"
  private let notificationsChannelName = "chat.intergalactic.app/ios_notifications"
  private let secureRecoveryKeyChannelName = "chat.intergalactic.app/secure_recovery_key"
  private let secureRecoveryKeyService = "chat.intergalactic.app.matrix_recovery_key"
  private let storyVideoExportChannelName = "chat.intergalactic.app/story_video_export"
  private let voiceRecorderChannelName = "chat.intergalactic.app/voice_recorder"

  private var notificationsChannel: FlutterMethodChannel?
  private var inboundShareChannel: FlutterMethodChannel?
  private var pushTokenHex: String?
  private var lastNotificationUserInfo: [String: Any]?
  /// Unacknowledged notification responses, oldest first.
  ///
  /// A FIFO queue, NOT a single optional. Each accepted action already gets its
  /// own background assertion keyed by response id, so two actions in quick
  /// succession both keep the app alive - but a single slot meant the second
  /// payload overwrote the first before Dart ever read it, and the first inline
  /// reply was silently dropped when its assertion expired. The storage now
  /// matches the assertions it is paired with.
  private var pendingNotificationResponses: [[String: Any]] = []

  /// Silent-wake bookkeeping (`didReceiveRemoteNotification`): one entry per
  /// wake iOS handed us, keyed by a wake id, holding the completion handler
  /// and the background assertion that keeps the process alive while Dart
  /// catches up. Wake ids that Dart has not yet taken wait in
  /// `pendingRemoteWakes` for a cold-launched engine to drain.
  private struct RemoteWake {
    let assertionToken: String?
    let completionHandler: (UIBackgroundFetchResult) -> Void
    /// APNs routing identifiers are retained only while this wake is pending.
    /// Dart uses them for the developer-only E10 backup measurement and never
    /// logs or persists them.
    let route: [String: String]?
    /// When iOS handed us this wake, on the same monotonic clock the
    /// deadline below is scheduled against. Dart needs it because its own
    /// budget must be what is LEFT of the deadline, and on a cold launch
    /// the engine boot happens between these two points.
    let startedAt: DispatchTime
  }
  private var remoteWakes: [String: RemoteWake] = [:]
  private var pendingRemoteWakes: [String] = []
  private static let remoteWakeDeadline: TimeInterval = 25
  /// The legacy SharedPreferences Foundation backend stores Dart preference
  /// keys in the standard defaults suite with this prefix. Missing values are
  /// deliberately false: E10 route metadata is developer-only.
  private static let developerModePreferenceKey = "flutter.developer_mode"

  /// Far above any real burst of notification actions; a backstop against a
  /// pathological loop rather than a working limit.
  private static let maxPendingNotificationResponses = 16
  private var mobileCallBackgroundActive = false
  private var mobileCallBackgroundRoomName: String?
  private var mobileCallBackgroundUsesMicrophone = false
  private var mobileCallBackgroundUsesCamera = false
  private var mobileCallBackgroundChannel: FlutterMethodChannel?
  private var callPiPCoordinatorStorage: Any?
  private var mobileCallPictureInPictureController: AVPictureInPictureController?
  private var mobileCallPictureInPictureContentViewController: UIViewController?
  private weak var mobileCallPictureInPictureSourceView: UIView?
  private var mobileCallPictureInPictureSourceRect: CGRect?
  private var mobileCallPictureInPictureSessionId: String?
  private weak var mobileCallPictureInPictureSnapshotImageView: UIImageView?
  private var mobileCallPictureInPicturePossibleObservation: NSKeyValueObservation?
  private var mobileCallPictureInPictureStartTimeoutWorkItem: DispatchWorkItem?
  private var mobileCallPictureInPictureSnapshotTimer: Timer?
  private var pendingMobileCallPictureInPictureResult: FlutterResult?
  private var pendingCameraMediaPickerResult: FlutterResult?
  private var voiceRecorder: AVAudioRecorder?
  private var voiceRecorderUrl: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      configureAppGroupStorageChannel(binaryMessenger: controller.binaryMessenger)
      configureAppIconChannel(binaryMessenger: controller.binaryMessenger)
      configureBackgroundAssertionChannel(binaryMessenger: controller.binaryMessenger)
      configureBiometricsChannel(binaryMessenger: controller.binaryMessenger)
      configureCallAudioChannel(binaryMessenger: controller.binaryMessenger)
      configureCameraMediaPickerChannel(binaryMessenger: controller.binaryMessenger)
      ImageCutoutChannel.register(binaryMessenger: controller.binaryMessenger)
      configureInboundShareChannel(binaryMessenger: controller.binaryMessenger)
      configureLocalMediaControlsChannel(binaryMessenger: controller.binaryMessenger)
      configureMediaSaverChannel(binaryMessenger: controller.binaryMessenger)
      configureMediaShareChannel(binaryMessenger: controller.binaryMessenger)
      configureMobileCallBackgroundChannel(binaryMessenger: controller.binaryMessenger)
      configureNotificationsChannel(binaryMessenger: controller.binaryMessenger)
      configureSecureRecoveryKeyChannel(binaryMessenger: controller.binaryMessenger)
      configureStoryVideoExportChannel(binaryMessenger: controller.binaryMessenger)
      configureVoiceRecorderChannel(binaryMessenger: controller.binaryMessenger)
    }

    if application.applicationState != .background,
      let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      captureNotificationUserInfo(
        remoteNotification,
        actionIdentifier: UNNotificationDefaultActionIdentifier
      )
    }

    registerForRemoteNotificationsIfAuthorized(result: nil)

    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    UNUserNotificationCenter.current().delegate = self
    return launched
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    deliverPendingNotificationResponse()
  }

  /// Short, non-reversible fingerprint of an APNs device token.
  ///
  /// The raw token is never logged: `log-guidance.md` forbids logging tokens,
  /// and an APNs token is the routing credential for this device. A SHA-256
  /// prefix is enough to answer the question that matters when notifications go
  /// silent - "is the token the app holds the same one the Matrix pusher was
  /// registered with?" - by comparing fingerprints rather than secrets.
  private func pushTokenFingerprint(_ tokenHex: String) -> String {
    guard let data = tokenHex.data(using: .utf8) else { return "unavailable" }
    return SHA256.hash(data: data)
      .prefix(4)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // The Share Extension may open space.ourgalaxy://share/v1/<token> to
    // foreground us. Claiming it here does NOT deliver the share: the URL
    // carries no payload and is never treated as an acknowledgement. Opening
    // the app is itself the trigger, because becoming active runs the same
    // App Group drain that a manual open runs - so a share arrives exactly
    // once whether or not the launch worked.
    //
    // `space.ourgalaxy` is NOT ours alone - flutter_web_auth_2 uses it for the
    // login callback - so anything that is not exactly the handoff shape must
    // fall through to super, or this override silently breaks sign-in.
    if InboundShareSessionStore.token(fromHandoff: url) != nil {
      NSLog("intergalactic_ios_share event=host_launched_by_extension")
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
    let tokenChanged = tokenHex != pushTokenHex
    let hadToken = pushTokenHex != nil
    pushTokenHex = tokenHex
    if tokenChanged {
      notificationsChannel?.invokeMethod("pushTokenUpdated", arguments: pushTokenHex)
    }
    // BUG-179: notifications can stop arriving after the app is closed for
    // hours, and the token lifecycle was entirely unlogged, so a device log
    // could not distinguish "APNs never delivered" from "the app never held a
    // usable token". forwarded=false with changed=false is the normal steady
    // state; forwarded=false with changed=true would mean Dart was not told.
    NSLog(
      // %ld, not %d: tokenHex.count is a Swift Int, which is 64-bit on every
      // device this ships to, and %d reads 32. It happens to print correctly
      // for a 64-char token on little-endian, but a length that silently
      // depends on endianness is the wrong thing to put in the log you reach
      // for when notifications are already behaving inexplicably.
      "intergalactic_ios_push event=token_received fp=%@ len=%ld changed=%@ had_previous=%@ forwarded=%@",
      pushTokenFingerprint(tokenHex),
      tokenHex.count,
      String(tokenChanged),
      String(hadToken),
      String(tokenChanged && notificationsChannel != nil)
    )
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // Only surfaced to Dart when no token was ever obtained, so a failure after
    // a good registration is silent by design - log it either way.
    let surfaced = pushTokenHex == nil
    if surfaced {
      notificationsChannel?.invokeMethod(
        "pushTokenRegistrationFailed",
        arguments: error.localizedDescription
      )
    }
    NSLog(
      "intergalactic_ios_push event=token_registration_failed has_token=%@ surfaced=%@ error=%@",
      String(pushTokenHex != nil),
      String(surfaced),
      error.localizedDescription
    )
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  /// A push rendered by the Notification Service Extension arriving while
  /// the app is in the foreground is NOT presented. The app's own notifier
  /// covers the foreground - it knows the active room, the snoozes and the
  /// preview choice - and the dedupe modifier only sees notifications that
  /// were presented, so presenting the extension's copy here would put a
  /// banner over the very room the user is reading. Before this override the
  /// same outcome held by accident: the local-notifications plugin returns
  /// without calling the completion handler for notifications it did not
  /// post. Everything without our routing ids goes to super as before.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    let isIntergalacticRemote =
      notificationString(userInfo, keys: ["room_id", "roomId", "roomID"]) != nil
      && notificationString(userInfo, keys: ["client_id", "clientId", "clientID"]) != nil
      && notification.request.trigger is UNPushNotificationTrigger
    if isIntergalacticRemote {
      NSLog("intergalactic_ios_notification_foreground source=apns presented=false")
      completionHandler([])
      return
    }
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  /// The `content-available` wake. Until this override existed the engine's
  /// default forwarded the wake to plugins, none handled it, and the
  /// completion was answered with no data at once: the app woke and did
  /// nothing, which is why room keys arrived only when the owner next opened
  /// the app. Now the wake is handed to Dart under a background assertion;
  /// Dart re-establishes the released databases, drains one short sync per
  /// account so pending to-device room keys are stored, releases again, and
  /// completes the wake. A hard deadline completes it regardless, so iOS is
  /// never left waiting and the assertion never leaks. Pushes without our
  /// routing shape go to super as before.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    let aps = userInfo["aps"] as? [AnyHashable: Any]
    let contentAvailable = (aps?["content-available"] as? Int) == 1
    let ours = notificationString(userInfo, keys: ["client_id", "clientId", "clientID"]) != nil
    guard contentAvailable, ours else {
      super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
      return
    }
    let wakeId = UUID().uuidString
    let token = beginBackgroundAssertion(name: "intergalactic.remote-wake") { [weak self] in
      self?.endRemoteWake(wakeId: wakeId, result: .noData, reason: "expired")
    }
    remoteWakes[wakeId] = RemoteWake(
      assertionToken: token,
      completionHandler: completionHandler,
      // This guard is intentionally native and precedes route extraction.
      // Developer-mode policy is a data-boundary rule, not merely a decision
      // about whether Dart eventually runs its diagnostic probe.
      route: developerModeEnabledForE10Measurement() ? remoteWakeRoute(userInfo) : nil,
      startedAt: .now()
    )
    pendingRemoteWakes.append(wakeId)
    NSLog(
      "intergalactic_ios_remote_wake result=began app_state=%@ channel=%@",
      application.applicationState == .active ? "active" : "background",
      notificationsChannel == nil ? "absent" : "present"
    )
    notificationsChannel?.invokeMethod(
      "remoteWakeReceived",
      arguments: remoteWakePayload(wakeId)
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.remoteWakeDeadline) { [weak self] in
      self?.endRemoteWake(wakeId: wakeId, result: .noData, reason: "deadline")
    }
  }

  private func endRemoteWake(wakeId: String, result: UIBackgroundFetchResult, reason: String) {
    guard let wake = remoteWakes.removeValue(forKey: wakeId) else { return }
    pendingRemoteWakes.removeAll { $0 == wakeId }
    NSLog("intergalactic_ios_remote_wake result=ended reason=%@", reason)
    // Order matters: tell iOS the work is done, then release the assertion.
    wake.completionHandler(result)
    if let token = wake.assertionToken {
      endBackgroundAssertion(token: token, reason: reason)
    }
  }

  /// Hands out a queued wake id and REMOVES it, so the cold-launch drain and a
  /// `remoteWakeReceived` push cannot both take the same one. Double-handling
  /// was harmless - the release trigger serialises and `endRemoteWake` is
  /// idempotent - but it spent a second catch-up out of a budget that matters.
  private func handleTakePendingRemoteWake(result: @escaping FlutterResult) {
    guard let wakeId = pendingRemoteWakes.first else {
      result(nil)
      return
    }
    pendingRemoteWakes.removeFirst()
    // A map, not the bare id: this is the cold-launch path, so the engine
    // boot has already spent part of the deadline and only native can say
    // how much.
    result(remoteWakePayload(wakeId))
  }

  private func remoteWakePayload(_ wakeId: String) -> [String: Any] {
    var payload: [String: Any] = [
      "wake_id": wakeId,
      "native_elapsed_ms": remoteWakeElapsedMs(wakeId)
    ]
    if let route = remoteWakes[wakeId]?.route {
      payload["route"] = route
    }
    return payload
  }

  private func remoteWakeRoute(_ userInfo: [AnyHashable: Any]) -> [String: String]? {
    guard let clientId = notificationString(userInfo, keys: ["client_id", "clientId", "clientID"]),
      let roomId = notificationString(userInfo, keys: ["room_id", "roomId", "roomID"]),
      let eventId = notificationString(userInfo, keys: ["event_id", "eventId", "eventID"])
    else {
      return nil
    }
    return ["client_id": clientId, "room_id": roomId, "event_id": eventId]
  }

  /// Reads the persisted Flutter Developer Mode setting directly because a
  /// silent wake can arrive before Dart has initialized. The false default
  /// prevents client, room, and event identifiers crossing the native-to-Dart
  /// bridge for ordinary notification delivery.
  private func developerModeEnabledForE10Measurement() -> Bool {
    UserDefaults.standard.bool(forKey: Self.developerModePreferenceKey)
  }

  /// Answers "how long have you been holding this wake?" at the moment Dart
  /// asks, which is not the moment native told Dart about it.
  ///
  /// The value stamped into `remoteWakeReceived` is measured when native
  /// SENDS. On a cold background launch the channel already exists - plugin
  /// registration runs long before Dart's own startup - so the wake takes the
  /// channel path, not `takePendingRemoteWake`, and Flutter buffers the
  /// message until the Dart handler is set. The engine boot then falls between
  /// native's stamp and Dart's stopwatch, and is charged to neither. Asking
  /// again here is the only way to see it. `nil` means the wake is already
  /// finished, so Dart keeps whatever it was told.
  private func handleRemoteWakeElapsed(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let wakeId = arguments["wake_id"] as? String, !wakeId.isEmpty,
      remoteWakes[wakeId] != nil
    else {
      result(nil)
      return
    }
    result(remoteWakeElapsedMs(wakeId))
  }

  /// Milliseconds since iOS handed us this wake, 0 if it is already gone.
  private func remoteWakeElapsedMs(_ wakeId: String) -> Int {
    guard let wake = remoteWakes[wakeId] else { return 0 }
    let now = DispatchTime.now().uptimeNanoseconds
    let started = wake.startedAt.uptimeNanoseconds
    guard now > started else { return 0 }
    return Int((now - started) / 1_000_000)
  }

  private func handleCompleteRemoteWake(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let wakeId = arguments["wake_id"] as? String, !wakeId.isEmpty
    else {
      result(false)
      return
    }
    let outcome = (arguments["result"] as? String) ?? "no_data"
    let fetchResult: UIBackgroundFetchResult
    switch outcome {
    case "new_data": fetchResult = .newData
    case "failed": fetchResult = .failed
    default: fetchResult = .noData
    }
    let known = remoteWakes[wakeId] != nil
    endRemoteWake(wakeId: wakeId, result: fetchResult, reason: "dart_" + outcome)
    result(known)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let handled = captureNotificationResponse(response)
    if handled {
      NSLog(
        "intergalactic_ios_notification_response_consumed source=apns-response action_present=%@",
        response.actionIdentifier.isEmpty ? "false" : "true"
      )
      // BUG-295. Calling completionHandler() here told iOS the work was done
      // before any Dart had run - before the method-channel invoke was even
      // dispatched, and long before room.sendMessage resolved. With no
      // background assertion the app was then free to suspend, so a reply typed
      // while backgrounded did nothing until the user refocused the app.
      //
      // Hold an assertion instead and defer the completion handler until Dart
      // acknowledges, which it does after the send attempt resolves.
      beginNotificationResponseTask(
        responseId: pendingNotificationResponses.last?["response_id"] as? String,
        completionHandler: completionHandler
      )
      return
    }

    NSLog(
      "intergalactic_ios_notification_response_forwarded source=apns-response reason=no_intergalactic_route"
    )
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  /// The event ids of remote notifications still in Notification Center.
  /// The Notification Service Extension renders a push into a notification
  /// whose userInfo keeps the gateway's routing ids, so the app's own
  /// notifier can tell which events the extension already showed and not
  /// show them a second time. Local notifications carry no event id and are
  /// not listed. Ids only: nothing from the content is returned.
  private func handleDeliveredRemoteEventIds(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
      var eventIds: [String] = []
      for notification in notifications {
        let content = notification.request.content
        // Remote (push-triggered) only: the app's own local notifications use
        // the same rich category, so the category alone does not name the
        // producer - the trigger does. Then only what the extension RENDERED:
        // a generic fallback (the gateway's own content, no category) must not
        // stop the app from showing the decrypted message once it has the
        // room key; the app removes that fallback when it posts its own (see
        // removeDeliveredRemoteNotification).
        guard notification.request.trigger is UNPushNotificationTrigger,
          content.categoryIdentifier == self.extensionRenderedCategory
        else { continue }
        if let eventId = self.notificationString(content.userInfo, keys: ["event_id", "eventId", "eventID"]) {
          eventIds.append(eventId)
        }
      }
      DispatchQueue.main.async {
        result(eventIds)
      }
    }
  }

  /// The category the Notification Service Extension sets on content it
  /// rendered itself (NotificationService.swift, richMessageCategory).
  private let extensionRenderedCategory = "chat.intergalactic.rich_message.v1"

  /// Removes the remote notifications for one event, rendered or generic,
  /// because the app is about to post its own for it. Ids only; nothing is
  /// read from the content.
  private func handleRemoveDeliveredRemoteNotification(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let eventId = arguments["event_id"] as? String, !eventId.isEmpty
    else {
      result(false)
      return
    }
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications { notifications in
      let identifiers = notifications.compactMap { notification -> String? in
        guard notification.request.trigger is UNPushNotificationTrigger else { return nil }
        let userInfo = notification.request.content.userInfo
        guard self.notificationString(userInfo, keys: ["event_id", "eventId", "eventID"]) == eventId else { return nil }
        return notification.request.identifier
      }
      if !identifiers.isEmpty {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
      }
      DispatchQueue.main.async {
        result(!identifiers.isEmpty)
      }
    }
  }

  /// A room becomes read only after the timeline reaches its newest event.
  /// Remove that room's delivered APNs alerts, including generic fallbacks;
  /// Flutter's local-notification enumeration cannot see these requests.
  private func handleRemoveDeliveredRemoteNotificationsForRoom(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let clientId = arguments["client_id"] as? String, !clientId.isEmpty,
      let roomId = arguments["room_id"] as? String, !roomId.isEmpty
    else {
      result(0)
      return
    }
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications { notifications in
      let identifiers = notifications.compactMap { notification -> String? in
        guard notification.request.trigger is UNPushNotificationTrigger else { return nil }
        let userInfo = notification.request.content.userInfo
        guard self.notificationString(userInfo, keys: ["client_id", "clientId", "clientID"]) == clientId,
          self.notificationString(userInfo, keys: ["room_id", "roomId", "roomID"]) == roomId
        else { return nil }
        return notification.request.identifier
      }
      if !identifiers.isEmpty {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
      }
      DispatchQueue.main.async {
        result(identifiers.count)
      }
    }
  }

  private func configureAppIconChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: appIconChannelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "app_icon_unavailable", message: "App icon bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "setAppIcon":
        self.handleSetAppIcon(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleSetAppIcon(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard UIApplication.shared.supportsAlternateIcons else {
      result(false)
      return
    }

    let arguments = call.arguments as? [String: Any]
    let iconName = (arguments?["iconName"] as? String)?.nilIfEmpty
    let desiredIconName = iconName

    if UIApplication.shared.alternateIconName == desiredIconName {
      result(true)
      return
    }

    UIApplication.shared.setAlternateIconName(desiredIconName) { error in
      if let error {
        result(
          FlutterError(
            code: "app_icon_set_failed",
            message: error.localizedDescription,
            details: desiredIconName
          )
        )
      } else {
        result(true)
      }
    }
  }

  private func configureBiometricsChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: biometricsChannelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "biometrics_unavailable", message: "Biometric bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "getBiometricAvailability":
        self.handleBiometricAvailability(result: result)
      case "authenticate":
        self.handleBiometricAuthentication(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureCallAudioChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: callAudioChannelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "call_audio_unavailable", message: "Call audio bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "prepareForCall":
        self.handlePrepareCallAudio(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handlePrepareCallAudio(result: @escaping FlutterResult) {
    requestVoiceRecordingPermission { [weak self] granted in
      DispatchQueue.main.async {
        guard let self = self else {
          result(FlutterError(code: "call_audio_unavailable", message: "Call audio bridge unavailable.", details: nil))
          return
        }

        guard granted else {
          result(self.callAudioSessionSnapshot(microphonePermission: "denied"))
          return
        }

        let audioSession = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = [
          .allowBluetooth,
          .allowBluetoothA2DP,
          .allowAirPlay,
          .defaultToSpeaker,
        ]

        do {
          try audioSession.setCategory(.playAndRecord, mode: .default, options: options)
          try audioSession.setActive(true)
          result(self.callAudioSessionSnapshot(microphonePermission: "granted"))
        } catch {
          result(
            FlutterError(
              code: "call_audio_session_failed",
              message: error.localizedDescription,
              details: self.callAudioSessionSnapshot(microphonePermission: "granted")
            )
          )
        }
      }
    }
  }

  private func configureCameraMediaPickerChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: cameraMediaPickerChannelName,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "camera_picker_unavailable", message: "Camera picker bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "pickCameraMedia":
        self.handlePickCameraMedia(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handlePickCameraMedia(result: @escaping FlutterResult) {
    guard pendingCameraMediaPickerResult == nil else {
      result(FlutterError(code: "camera_picker_active", message: "A camera picker is already active.", details: nil))
      return
    }

    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      result(FlutterError(code: "camera_unavailable", message: "Camera capture is not available on this device.", details: nil))
      return
    }

    guard let presenter = topViewController(from: window?.rootViewController) else {
      result(FlutterError(code: "camera_presenter_unavailable", message: "No active view controller is available.", details: nil))
      return
    }

    let picker = UIImagePickerController()
    picker.sourceType = .camera
    let availableTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? []
    let supportedTypes = ["public.image", "public.movie"].filter { availableTypes.contains($0) }
    guard !supportedTypes.isEmpty else {
      result(FlutterError(code: "camera_media_unavailable", message: "Camera photo and video capture are not available.", details: nil))
      return
    }

    picker.mediaTypes = supportedTypes
    picker.videoQuality = .typeHigh
    picker.delegate = self
    pendingCameraMediaPickerResult = result
    presenter.present(picker, animated: true)
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    if let navigationController = root as? UINavigationController {
      return topViewController(from: navigationController.visibleViewController)
    }

    if let tabController = root as? UITabBarController {
      return topViewController(from: tabController.selectedViewController)
    }

    if let presented = root?.presentedViewController {
      return topViewController(from: presented)
    }

    return root
  }

  private func callAudioSessionSnapshot(microphonePermission: String) -> [String: Any] {
    let audioSession = AVAudioSession.sharedInstance()
    return [
      "supported": true,
      "microphonePermission": microphonePermission,
      "category": audioSession.category.rawValue,
      "mode": audioSession.mode.rawValue,
      "sampleRate": audioSession.sampleRate,
      "inputPorts": audioSession.currentRoute.inputs.map { $0.portType.rawValue },
      "outputPorts": audioSession.currentRoute.outputs.map { $0.portType.rawValue },
    ]
  }

  private func configureMobileCallBackgroundChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: mobileCallBackgroundChannelName,
      binaryMessenger: binaryMessenger
    )
    mobileCallBackgroundChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "mobile_call_background_unavailable", message: "Mobile call background bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "setCallBackgroundActive":
        self.handleSetCallBackgroundActive(call: call, result: result)
      case "getPopoutPresentationState":
        result(self.mobileCallPopoutPresentationState())
      case "enterPictureInPicture":
        self.handleEnterMobileCallPictureInPicture(call: call, result: result)
      case "exitPictureInPicture":
        self.handleExitMobileCallPictureInPicture(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleSetCallBackgroundActive(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let active = arguments["active"] as? Bool ?? false
    let roomName = (arguments["roomName"] as? String)?.nilIfEmpty
    let usesMicrophone = arguments["usesMicrophone"] as? Bool ?? false
    let usesCamera = arguments["usesCamera"] as? Bool ?? false

    mobileCallBackgroundRoomName = roomName
    mobileCallBackgroundUsesMicrophone = usesMicrophone
    mobileCallBackgroundUsesCamera = usesCamera

    NSLog(
      "intergalactic_ios_call_background event=set_requested active=%@ mic=%@ camera=%@ room=%@",
      String(active),
      String(usesMicrophone),
      String(usesCamera),
      roomName ?? "<none>"
    )

    if active {
      activateMobileCallBackgroundAudio(
        roomName: roomName,
        usesMicrophone: usesMicrophone,
        usesCamera: usesCamera,
        result: result
      )
      return
    }

    deactivateMobileCallBackgroundAudio(result: result)
  }

  private func activateMobileCallBackgroundAudio(
    roomName: String?,
    usesMicrophone: Bool,
    usesCamera: Bool,
    result: @escaping FlutterResult
  ) {
    let audioSession = AVAudioSession.sharedInstance()
    let options: AVAudioSession.CategoryOptions = [
      .allowBluetooth,
      .allowBluetoothA2DP,
      .allowAirPlay,
      .defaultToSpeaker,
    ]
    let mode: AVAudioSession.Mode = usesCamera ? .videoChat : .voiceChat

    do {
      try audioSession.setCategory(.playAndRecord, mode: mode, options: options)
      try audioSession.setActive(true)
      mobileCallBackgroundActive = true
      NSLog(
        "intergalactic_ios_call_background event=activated mode=%@ mic=%@ camera=%@ room=%@",
        mode.rawValue,
        String(usesMicrophone),
        String(usesCamera),
        roomName ?? "<none>"
      )
      result(nil)
    } catch {
      NSLog(
        "intergalactic_ios_call_background event=activate_failed error=%@",
        error.localizedDescription
      )
      result(
        FlutterError(
          code: "mobile_call_background_audio_failed",
          message: error.localizedDescription,
          details: mobileCallBackgroundSessionSnapshot()
        )
      )
    }
  }

  private func deactivateMobileCallBackgroundAudio(result: @escaping FlutterResult) {
    let wasActive = mobileCallBackgroundActive
    mobileCallBackgroundActive = false
    mobileCallBackgroundRoomName = nil
    mobileCallBackgroundUsesMicrophone = false
    mobileCallBackgroundUsesCamera = false
    stopMobileCallPictureInPictureIfNeeded()

    do {
      if wasActive {
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
      }
      NSLog("intergalactic_ios_call_background event=deactivated wasActive=%@", String(wasActive))
      result(nil)
    } catch {
      NSLog(
        "intergalactic_ios_call_background event=deactivate_failed error=%@",
        error.localizedDescription
      )
      result(
        FlutterError(
          code: "mobile_call_background_deactivate_failed",
          message: error.localizedDescription,
          details: mobileCallBackgroundSessionSnapshot()
        )
      )
    }
  }

  private func mobileCallBackgroundSessionSnapshot() -> [String: Any] {
    let audioSession = AVAudioSession.sharedInstance()
    return [
      "supported": true,
      "active": mobileCallBackgroundActive,
      "roomName": mobileCallBackgroundRoomName ?? "",
      "usesMicrophone": mobileCallBackgroundUsesMicrophone,
      "usesCamera": mobileCallBackgroundUsesCamera,
      "category": audioSession.category.rawValue,
      "mode": audioSession.mode.rawValue,
      "sampleRate": audioSession.sampleRate,
      "inputPorts": audioSession.currentRoute.inputs.map { $0.portType.rawValue },
      "outputPorts": audioSession.currentRoute.outputs.map { $0.portType.rawValue },
    ]
  }

  private func handleEnterMobileCallPictureInPicture(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 15.0, *) else {
      NSLog("intergalactic_ios_call_pip event=start_rejected reason=ios_version_below_15")
      result(false)
      return
    }

    mobileCallPiPCoordinator().enter(
      call: call,
      result: result,
      callBackgroundActive: mobileCallBackgroundActive,
      sourceView: window?.rootViewController?.view
    )
  }

  private func handleExitMobileCallPictureInPicture(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let reason = (arguments["reason"] as? String)?.nilIfEmpty ?? "requested"
    if #available(iOS 15.0, *) {
      mobileCallPiPCoordinator().stop(reason: reason)
    } else {
      stopMobileCallPictureInPictureIfNeeded(reason: reason)
    }
    result(true)
  }

  @available(iOS 15.0, *)
  private func mobileCallPiPCoordinator() -> CallPiPCoordinator {
    if let coordinator = callPiPCoordinatorStorage as? CallPiPCoordinator {
      return coordinator
    }

    let coordinator = CallPiPCoordinator(
      presentationChanged: { [weak self] state in
        self?.mobileCallBackgroundChannel?.invokeMethod(
          "mobileCallPresentationChanged",
          arguments: state
        )
      },
      actionRequested: { [weak self] action in
        self?.mobileCallBackgroundChannel?.invokeMethod(
          "mobileCallPictureInPictureAction",
          arguments: ["action": action]
        )
      }
    )
    callPiPCoordinatorStorage = coordinator
    return coordinator
  }

  @available(iOS 15.0, *)
  private func scheduleMobileCallPictureInPictureStart(
    _ controller: AVPictureInPictureController
  ) {
    mobileCallPictureInPicturePossibleObservation?.invalidate()
    mobileCallPictureInPictureStartTimeoutWorkItem?.cancel()

    let startIfPossible: () -> Void = { [weak self, weak controller] in
      guard
        let self = self,
        let controller = controller,
        self.mobileCallPictureInPictureController === controller,
        self.pendingMobileCallPictureInPictureResult != nil
      else {
        return
      }

      guard controller.isPictureInPicturePossible else {
        return
      }

      self.mobileCallPictureInPicturePossibleObservation?.invalidate()
      self.mobileCallPictureInPicturePossibleObservation = nil
      self.mobileCallPictureInPictureStartTimeoutWorkItem?.cancel()
      self.mobileCallPictureInPictureStartTimeoutWorkItem = nil
      NSLog("intergalactic_ios_call_pip event=start_requested possible=true")
      controller.startPictureInPicture()
    }

    mobileCallPictureInPicturePossibleObservation = controller.observe(
      \.isPictureInPicturePossible,
      options: [.initial, .new]
    ) { _, _ in
      DispatchQueue.main.async {
        startIfPossible()
      }
    }

    let timeout = DispatchWorkItem { [weak self, weak controller] in
      guard
        let self = self,
        let controller = controller,
        self.mobileCallPictureInPictureController === controller,
        self.pendingMobileCallPictureInPictureResult != nil
      else {
        return
      }

      if controller.isPictureInPicturePossible {
        startIfPossible()
        return
      }

      NSLog("intergalactic_ios_call_pip event=start_failed reason=not_possible_timeout")
      self.resolvePendingMobileCallPictureInPictureStart(false)
      self.clearMobileCallPictureInPictureContentState()
      self.mobileCallPictureInPictureController = nil
      self.mobileCallPictureInPictureContentViewController = nil
      self.notifyMobileCallPresentationChanged()
    }
    mobileCallPictureInPictureStartTimeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: timeout)
  }

  @available(iOS 15.0, *)
  private func mobileCallPictureInPicturePreferredSize(call: FlutterMethodCall) -> CGSize {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let numerator = max(1, arguments["aspectRatioNumerator"] as? Int ?? 16)
    let denominator = max(1, arguments["aspectRatioDenominator"] as? Int ?? 9)
    let width: CGFloat = 320
    let height = max(180, width * CGFloat(denominator) / CGFloat(numerator))
    return CGSize(width: width, height: height)
  }

  private func mobileCallPictureInPictureSourceRect(
    call: FlutterMethodCall,
    sourceView: UIView
  ) -> CGRect? {
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard
      let left = arguments["sourceRectLeft"] as? NSNumber,
      let top = arguments["sourceRectTop"] as? NSNumber,
      let right = arguments["sourceRectRight"] as? NSNumber,
      let bottom = arguments["sourceRectBottom"] as? NSNumber
    else {
      return nil
    }

    let scale = max(sourceView.window?.screen.scale ?? UIScreen.main.scale, 1)
    let rect = CGRect(
      x: CGFloat(truncating: left) / scale,
      y: CGFloat(truncating: top) / scale,
      width: max(1, CGFloat(truncating: right) - CGFloat(truncating: left)) / scale,
      height: max(1, CGFloat(truncating: bottom) - CGFloat(truncating: top)) / scale
    )
    let clipped = rect.intersection(sourceView.bounds)
    return clipped.isNull || clipped.isEmpty ? nil : clipped
  }

  private func configureMobileCallPictureInPictureContentView(
    _ view: UIView,
    sourceView: UIView,
    sourceRect: CGRect?
  ) {
    stopMobileCallPictureInPictureSnapshotTimer()
    view.subviews.forEach { $0.removeFromSuperview() }
    view.backgroundColor = UIColor.black

    let imageView = UIImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.backgroundColor = UIColor.black
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    view.addSubview(imageView)

    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: view.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    mobileCallPictureInPictureSourceView = sourceView
    mobileCallPictureInPictureSourceRect = sourceRect
    mobileCallPictureInPictureSnapshotImageView = imageView

    updateMobileCallPictureInPictureSnapshot(afterScreenUpdates: true)
    startMobileCallPictureInPictureSnapshotTimer()
  }

  private func startMobileCallPictureInPictureSnapshotTimer() {
    let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
      self?.updateMobileCallPictureInPictureSnapshot()
    }
    RunLoop.main.add(timer, forMode: .common)
    mobileCallPictureInPictureSnapshotTimer = timer
  }

  private func stopMobileCallPictureInPictureSnapshotTimer() {
    mobileCallPictureInPictureSnapshotTimer?.invalidate()
    mobileCallPictureInPictureSnapshotTimer = nil
  }

  private func updateMobileCallPictureInPictureSnapshot(afterScreenUpdates: Bool = false) {
    guard
      let sourceView = mobileCallPictureInPictureSourceView,
      let imageView = mobileCallPictureInPictureSnapshotImageView
    else {
      return
    }

    let sourceBounds = sourceView.bounds
    guard !sourceBounds.isEmpty else {
      return
    }

    let sourceRect = mobileCallPictureInPictureSourceRect ?? sourceBounds
    let clippedRect = sourceRect.intersection(sourceBounds)
    guard !clippedRect.isNull, !clippedRect.isEmpty else {
      return
    }

    let format = UIGraphicsImageRendererFormat()
    format.scale = sourceView.window?.screen.scale ?? UIScreen.main.scale
    format.opaque = true
    var didDraw = false
    let renderer = UIGraphicsImageRenderer(size: clippedRect.size, format: format)
    let image = renderer.image { context in
      UIColor.black.setFill()
      context.fill(CGRect(origin: .zero, size: clippedRect.size))
      didDraw = sourceView.drawHierarchy(
        in: CGRect(
          x: -clippedRect.minX,
          y: -clippedRect.minY,
          width: sourceBounds.width,
          height: sourceBounds.height
        ),
        afterScreenUpdates: afterScreenUpdates
      )
    }

    if didDraw {
      imageView.image = image
    }
  }

  private func clearMobileCallPictureInPictureContentState() {
    stopMobileCallPictureInPictureSnapshotTimer()
    mobileCallPictureInPicturePossibleObservation?.invalidate()
    mobileCallPictureInPicturePossibleObservation = nil
    mobileCallPictureInPictureStartTimeoutWorkItem?.cancel()
    mobileCallPictureInPictureStartTimeoutWorkItem = nil
    mobileCallPictureInPictureSourceView = nil
    mobileCallPictureInPictureSourceRect = nil
    mobileCallPictureInPictureSessionId = nil
    mobileCallPictureInPictureSnapshotImageView = nil
  }

  private func stopMobileCallPictureInPictureIfNeeded(reason: String = "call_inactive") {
    if #available(iOS 15.0, *) {
      mobileCallPiPCoordinator().stop(reason: reason)
      return
    }

    guard let controller = mobileCallPictureInPictureController else {
      return
    }

    if controller.isPictureInPictureActive {
      NSLog("intergalactic_ios_call_pip event=stop_requested reason=%@", reason)
      controller.stopPictureInPicture()
    } else {
      clearMobileCallPictureInPictureContentState()
      mobileCallPictureInPictureController = nil
      mobileCallPictureInPictureContentViewController = nil
      resolvePendingMobileCallPictureInPictureStart(false)
      notifyMobileCallPresentationChanged()
    }
  }

  private func mobileCallPopoutPresentationState() -> [String: Any] {
    if #available(iOS 15.0, *) {
      return mobileCallPiPCoordinator().presentationState
    }

    return [
      "pictureInPicture": mobileCallPictureInPictureController?.isPictureInPictureActive == true,
      "resizedPopout": false,
      "sessionId": mobileCallPictureInPictureSessionId ?? "",
    ]
  }

  private func notifyMobileCallPresentationChanged() {
    mobileCallBackgroundChannel?.invokeMethod(
      "mobileCallPresentationChanged",
      arguments: mobileCallPopoutPresentationState()
    )
  }

  private func notifyMobileCallPictureInPictureAction(_ action: String) {
    mobileCallBackgroundChannel?.invokeMethod(
      "mobileCallPictureInPictureAction",
      arguments: ["action": action]
    )
  }

  private func resolvePendingMobileCallPictureInPictureStart(_ value: Bool) {
    guard let result = pendingMobileCallPictureInPictureResult else {
      return
    }
    pendingMobileCallPictureInPictureResult = nil
    result(value)
  }

  private func configureSecureRecoveryKeyChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: secureRecoveryKeyChannelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "secure_recovery_key_unavailable", message: "Secure recovery-key bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "getStatus":
        self.handleSecureRecoveryKeyStatus(call: call, result: result)
      case "writeRecoveryKey":
        self.handleSecureRecoveryKeyWrite(call: call, result: result)
      case "readRecoveryKey":
        self.handleSecureRecoveryKeyRead(call: call, result: result)
      case "deleteRecoveryKey":
        self.handleSecureRecoveryKeyDelete(call: call, result: result)
      case "deleteAllRecoveryKeys":
        self.handleSecureRecoveryKeyDeleteAll(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleSecureRecoveryKeyDeleteAll(result: @escaping FlutterResult) {
    var query = secureRecoveryKeyServiceQuery()
    query[kSecClass as String] = kSecClassGenericPassword

    let status = SecItemDelete(query as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      result(true)
    } else {
      result(secureRecoveryKeychainError(status))
    }
  }

  private func configureLocalMediaControlsChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: localMediaControlsChannelName,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "local_media_unavailable", message: "Local media bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "getSnapshot":
        result(self.localMediaSnapshot())
      case "requestAuthorization":
        self.requestMediaLibraryAuthorization(result: result)
      case "play":
        MPMusicPlayerController.systemMusicPlayer.play()
        result(true)
      case "pause":
        MPMusicPlayerController.systemMusicPlayer.pause()
        result(true)
      case "togglePlayPause":
        let player = MPMusicPlayerController.systemMusicPlayer
        if player.playbackState == .playing {
          player.pause()
        } else {
          player.play()
        }
        result(true)
      case "skipPrevious":
        MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
        result(true)
      case "skipNext":
        MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - App Group storage (NSE Phase B)

  /// The shared container the Matrix account database moves into, and the
  /// data-protection class it relies on once it lives there (S&C condition
  /// B1: set on files AND directories, verified by read-back, re-asserted on
  /// every launch, and the move aborted when it cannot be set).
  ///
  /// Three methods: `getContainerPath`, `protectItem`, `readProtectionClass`.
  /// `protectItem` sets a file attribute on a caller-supplied path, so it is
  /// bounded the same way `handleNotificationPreviewFileProtection` is - it
  /// accepts nothing outside the App Group container. `readProtectionClass`
  /// additionally accepts the app's own Application Support tree, and only
  /// reads, so the class of the not-yet-moved database can be measured. Both
  /// roots and the candidate are compared with symlinks resolved, because on
  /// device the container is reported under `/private/var` and handed around
  /// as `/var`.
  ///
  /// Logging here carries an event and an error class. Never the path: the
  /// Dart side owes S&C condition B4 (no container path, no account, no
  /// listing in diagnostics) and this side keeps to the same rule.
  private func configureAppGroupStorageChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: appGroupStorageChannelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(
          code: "app_group_storage_unavailable",
          message: "App Group storage bridge unavailable.",
          details: nil
        ))
        return
      }

      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "getContainerPath":
        let container = self.appGroupContainerURL()
        if container == nil {
          NSLog("intergalactic_ios_app_group_storage event=no_app_group")
        }
        result(container?.path)
      case "protectItem":
        self.handleAppGroupProtectItem(path: arguments?["path"] as? String, result: result)
      case "readProtectionClass":
        self.handleAppGroupReadProtectionClass(
          path: arguments?["path"] as? String,
          result: result
        )
      case "excludeFromBackup":
        self.handleAppGroupExcludeFromBackup(
          path: arguments?["path"] as? String,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Marks an item inside the App Group container as excluded from backup
  /// (S&C D3 / C3 for the policy snapshot). Container-only, like
  /// `protectItem`; answers with what the resource reports afterwards.
  private func handleAppGroupExcludeFromBackup(path: String?, result: @escaping FlutterResult) {
    guard let target = appGroupStorageAllowedPath(path, allowApplicationSupport: false) else {
      result(FlutterError(
        code: "path_not_allowed",
        message: "Only items inside the App Group container can be excluded from backup.",
        details: nil
      ))
      return
    }
    var url = URL(fileURLWithPath: target)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
    } catch {
      NSLog(
        "intergalactic_ios_app_group_storage event=exclude_backup_failed code=%ld",
        (error as NSError).code
      )
      result(false)
      return
    }
    let readBack = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    result(readBack?.isExcludedFromBackup ?? false)
  }

  private func appGroupContainerURL() -> URL? {
    // The same group the inbound-share staging area uses; there is one App
    // Group on every target of this app.
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: inboundShareAppGroup)
  }

  private func resolvedPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private func isPath(_ candidate: String, under root: String) -> Bool {
    candidate == root || candidate.hasPrefix(root + "/")
  }

  /// The candidate's symlink-resolved path when it is inside the App Group
  /// container, or - when `allowApplicationSupport` - inside the app's own
  /// Application Support directory. Nil otherwise, and nil for a missing item.
  private func appGroupStorageAllowedPath(
    _ path: String?,
    allowApplicationSupport: Bool
  ) -> String? {
    guard let path, !path.isEmpty else {
      return nil
    }

    var roots: [String] = []
    if let container = appGroupContainerURL() {
      roots.append(resolvedPath(container))
    }
    if allowApplicationSupport {
      roots += NSSearchPathForDirectoriesInDomains(
        .applicationSupportDirectory, .userDomainMask, true
      ).map { resolvedPath(URL(fileURLWithPath: $0, isDirectory: true)) }
    }

    let candidate = resolvedPath(URL(fileURLWithPath: path))
    guard roots.contains(where: { isPath(candidate, under: $0) }),
      FileManager.default.fileExists(atPath: candidate)
    else {
      return nil
    }
    return candidate
  }

  private func appGroupProtectionClassRawValue(atPath path: String) -> String? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
      return nil
    }
    if let type = attributes[.protectionKey] as? FileProtectionType {
      return type.rawValue
    }
    if let raw = attributes[.protectionKey] as? String {
      return raw
    }
    return nil
  }

  private func handleAppGroupProtectItem(path: String?, result: @escaping FlutterResult) {
    guard let target = appGroupStorageAllowedPath(path, allowApplicationSupport: false) else {
      NSLog("intergalactic_ios_app_group_storage event=protect_rejected reason=path_not_allowed")
      result(FlutterError(
        code: "path_not_allowed",
        message: "Only items inside the App Group container can be protected.",
        details: nil
      ))
      return
    }

    do {
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: target
      )
    } catch {
      // The error's description names the path. The class of failure is
      // enough to act on.
      NSLog(
        "intergalactic_ios_app_group_storage event=protect_failed code=%ld",
        (error as NSError).code
      )
      result(FlutterError(
        code: "protection_set_failed",
        message: "Could not set the data-protection class.",
        details: nil
      ))
      return
    }

    // Read back, and hand Dart what the filesystem says rather than what was
    // asked for. Dart compares; a mismatch or a nil is a failed B1 check.
    result(appGroupProtectionClassRawValue(atPath: target))
  }

  private func handleAppGroupReadProtectionClass(path: String?, result: @escaping FlutterResult) {
    guard let target = appGroupStorageAllowedPath(path, allowApplicationSupport: true) else {
      result(FlutterError(
        code: "path_not_allowed",
        message: "Only items inside the App Group container or Application Support can be read.",
        details: nil
      ))
      return
    }
    result(appGroupProtectionClassRawValue(atPath: target))
  }

  // MARK: - Inbound share (U4)

  /// Shared App Group staging root.
  ///
  /// Android answers the same method with its own private cache directory,
  /// because there the host process stages the content itself. On iOS the Share
  /// Extension is a *separate process*, so the only directory both can reach is
  /// the App Group container. Returning a Runner-private path here would leave
  /// Dart looking in a directory the extension never wrote to.
  private func inboundShareStagingRoot() -> String? {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: inboundShareAppGroup
      )
    else { return nil }
    return container.appendingPathComponent(inboundShareStagingDirectory, isDirectory: true).path
  }

  /// On-disk session lifecycle, extracted so it can be unit-tested.
  /// See `InboundShareSessionStore` for the reservation protocol.
  private func inboundShareStore() -> InboundShareSessionStore? {
    guard let root = inboundShareStagingRoot() else { return nil }
    return InboundShareSessionStore(
      root: URL(fileURLWithPath: root, isDirectory: true),
      reservationTimeout: inboundShareReservationTimeout,
      sessionMaxAge: inboundShareSessionMaxAge
    )
  }

  private func reserveNextInboundShareSession() -> String? {
    guard let token = inboundShareStore()?.reserveNext() else { return nil }
    NSLog("intergalactic_ios_share event=session_reserved")
    return token
  }

  private func acknowledgeInboundShare(_ token: String) -> Bool {
    let ok = inboundShareStore()?.acknowledge(token) ?? false
    NSLog(
      "intergalactic_ios_share event=%@",
      ok ? "session_acknowledged" : "acknowledge_failed"
    )
    return ok
  }

  private func rejectInboundShare(_ token: String) -> Bool {
    let ok = inboundShareStore()?.reject(token) ?? false
    NSLog("intergalactic_ios_share event=%@", ok ? "session_rejected" : "reject_failed")
    return ok
  }

  /// Tells iOS about a conversation the user just sent to, so the share sheet
  /// can offer it as a suggestion next time.
  ///
  /// This is what makes `INSendMessageIntent` arrive in the Share Extension:
  /// without donated interactions the system has nothing to suggest, so the
  /// extension's `extensionContext.intent` is always nil and preselection never
  /// fires.
  ///
  /// PRIVACY: donating publishes the conversation's display name to iOS, where
  /// it can surface in the share sheet and Siri suggestions - on the lock screen
  /// among other places. That is the same class of disclosure as a notification
  /// preview, so the Dart caller gates this on the existing
  /// notification-preview privacy choice, which defaults to private. Nothing is
  /// donated unless the user has already opted into richer previews. No message
  /// content and no avatar are sent.
  private func donateConversation(
    roomId: String,
    displayName: String,
    result: @escaping FlutterResult
  ) {
    let recipient = INPerson(
      personHandle: INPersonHandle(value: roomId, type: .unknown),
      nameComponents: nil,
      displayName: displayName,
      image: nil,
      contactIdentifier: nil,
      customIdentifier: roomId
    )
    let intent = INSendMessageIntent(
      recipients: [recipient],
      outgoingMessageType: .outgoingMessageText,
      content: nil,
      speakableGroupName: INSpeakableString(spokenPhrase: displayName),
      conversationIdentifier: roomId,
      serviceName: nil,
      sender: nil,
      attachments: nil
    )
    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .outgoing
    // Group the donation under the room so a later send replaces the earlier
    // one instead of stacking duplicates in the system's suggestion store.
    interaction.groupIdentifier = roomId
    interaction.donate { error in
      if let error = error {
        NSLog("intergalactic_ios_share event=donate_failed error=%@", error.localizedDescription)
      } else {
        NSLog("intergalactic_ios_share event=donated")
      }
      DispatchQueue.main.async { result(error == nil) }
    }
  }

  private func configureInboundShareChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: inboundShareChannelName,
      binaryMessenger: binaryMessenger
    )
    inboundShareChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(
          FlutterError(
            code: "inbound_share_unavailable",
            message: "Inbound share bridge unavailable.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "inboundShareStagingRoot":
        guard let root = self.inboundShareStagingRoot() else {
          // An App Group that does not resolve is a provisioning fault, not a
          // runtime edge case - surface it instead of returning a path that
          // would silently stage nowhere the extension can see.
          NSLog("intergalactic_ios_share event=staging_root_unavailable")
          result(
            FlutterError(
              code: "inbound_share_no_app_group",
              message: "App Group container is unavailable.",
              details: nil
            )
          )
          return
        }
        result(root)
      case "consumePendingInboundShare":
        // Returns one session per call so Dart can drain them in a loop. The
        // session is only RESERVED here; Dart must acknowledge or reject it.
        // The scan itself is file I/O, so it runs off the platform thread and
        // replies on main.
        self.inboundShareQueue.async {
          let token = self.reserveNextInboundShareSession()
          DispatchQueue.main.async { result(token) }
        }
      case "acknowledgeInboundShare":
        guard let token = call.arguments as? String else {
          result(false)
          return
        }
        self.inboundShareQueue.async {
          let ok = self.acknowledgeInboundShare(token)
          DispatchQueue.main.async { result(ok) }
        }
      case "donateConversation":
        guard let args = call.arguments as? [String: Any],
          let roomId = (args["roomId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let displayName = (args["displayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !roomId.isEmpty, !displayName.isEmpty
        else {
          result(false)
          return
        }
        self.donateConversation(roomId: roomId, displayName: displayName, result: result)
      case "rejectInboundShare":
        guard let token = call.arguments as? String else {
          result(false)
          return
        }
        // Rejection deletes the staged session, which can be hundreds of
        // megabytes, so the channel must not wait on it either.
        self.inboundShareQueue.async {
          let ok = self.rejectInboundShare(token)
          DispatchQueue.main.async { result(ok) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureMediaSaverChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: mediaSaverChannelName,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "media_saver_unavailable", message: "Media saver bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "saveImageToPhotos":
        self.handleSaveImageToPhotos(call: call, result: result)
      case "saveMediaToPhotos":
        self.handleSaveMediaToPhotos(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleSaveImageToPhotos(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    guard let typedData = arguments?["bytes"] as? FlutterStandardTypedData,
      !typedData.data.isEmpty
    else {
      result(FlutterError(code: "invalid_arguments", message: "Image bytes are required.", details: nil))
      return
    }

    let fileName = (arguments?["filename"] as? String)?.nilIfEmpty ?? "intergalactic-image"

    requestPhotoAddAuthorization { [weak self] authorized in
      DispatchQueue.main.async {
        guard let self = self else {
          result(FlutterError(code: "media_saver_unavailable", message: "Media saver bridge unavailable.", details: nil))
          return
        }

        guard authorized else {
          result(FlutterError(code: "photo_permission_denied", message: "Photo library add permission was denied.", details: nil))
          return
        }

        self.savePhotoData(typedData.data, fileName: fileName, result: result)
      }
    }
  }

  private func requestPhotoAddAuthorization(completion: @escaping (Bool) -> Void) {
    if #available(iOS 14, *) {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      switch status {
      case .authorized, .limited:
        completion(true)
      case .notDetermined:
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          completion(status == .authorized || status == .limited)
        }
      case .denied, .restricted:
        completion(false)
      @unknown default:
        completion(false)
      }
      return
    }

    switch PHPhotoLibrary.authorizationStatus() {
    case .authorized:
      completion(true)
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization { status in
        completion(status == .authorized)
      }
    case .denied, .restricted:
      completion(false)
    @unknown default:
      completion(false)
    }
  }

  private func savePhotoData(_ data: Data, fileName: String, result: @escaping FlutterResult) {
    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = fileName
      request.addResource(with: .photo, data: data, options: options)
    }) { success, error in
      DispatchQueue.main.async {
        if success {
          result(true)
        } else {
          result(
            FlutterError(
              code: "photo_save_failed",
              message: error?.localizedDescription ?? "The image could not be saved to Photos.",
              details: nil
            )
          )
        }
      }
    }
  }

  /// Saves either image *or* video media to Photos, sourced from in-memory bytes
  /// or from a file already on disk. `saveImageToPhotos` stays as the
  /// image-and-bytes-only path so existing callers keep their exact behaviour.
  private func handleSaveMediaToPhotos(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let fileName = (arguments?["filename"] as? String)?.nilIfEmpty ?? "intergalactic-media"
    let mimeType = (arguments?["mimeType"] as? String)?.lowercased()
    let isVideo = mimeType?.hasPrefix("video/") ?? false

    let data = (arguments?["bytes"] as? FlutterStandardTypedData)?.data
    let path = (arguments?["path"] as? String)?.nilIfEmpty

    guard (data?.isEmpty == false) || path != nil else {
      result(FlutterError(code: "invalid_arguments", message: "Media bytes or a file path are required.", details: nil))
      return
    }

    requestPhotoAddAuthorization { [weak self] authorized in
      DispatchQueue.main.async {
        guard let self = self else {
          result(FlutterError(code: "media_saver_unavailable", message: "Media saver bridge unavailable.", details: nil))
          return
        }

        guard authorized else {
          result(FlutterError(code: "photo_permission_denied", message: "Photo library add permission was denied.", details: nil))
          return
        }

        self.saveMediaResource(
          data: data,
          path: path,
          fileName: fileName,
          isVideo: isVideo,
          result: result
        )
      }
    }
  }

  private func saveMediaResource(
    data: Data?,
    path: String?,
    fileName: String,
    isVideo: Bool,
    result: @escaping FlutterResult
  ) {
    let resourceType: PHAssetResourceType = isVideo ? .video : .photo

    // Prefer the on-disk file: it avoids holding a whole video in memory, and
    // lets Photos keep the original container untouched.
    let fileURL: URL? = {
      guard let path = path else { return nil }
      let candidate = URL(fileURLWithPath: path)
      return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }()

    guard fileURL != nil || (data?.isEmpty == false) else {
      result(
        FlutterError(
          code: "media_source_missing",
          message: "The media to save could not be read.",
          details: nil
        )
      )
      return
    }

    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = fileName
      // Never move: the caller still owns the source file (it is usually the
      // attachment about to be sent).
      options.shouldMoveFile = false

      if let fileURL = fileURL {
        request.addResource(with: resourceType, fileURL: fileURL, options: options)
      } else if let data = data {
        request.addResource(with: resourceType, data: data, options: options)
      }
    }) { success, error in
      DispatchQueue.main.async {
        if success {
          result(true)
        } else {
          result(
            FlutterError(
              code: "media_save_failed",
              message: error?.localizedDescription ?? "The media could not be saved to Photos.",
              details: nil
            )
          )
        }
      }
    }
  }

  private func configureMediaShareChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: mediaShareChannelName,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "media_share_unavailable", message: "Media share bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "shareFile":
        self.handleShareFile(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleShareFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    guard let typedData = arguments?["bytes"] as? FlutterStandardTypedData,
      !typedData.data.isEmpty
    else {
      result(FlutterError(code: "invalid_arguments", message: "File bytes are required.", details: nil))
      return
    }

    let fileName = sanitizeShareFileName(
      (arguments?["filename"] as? String)?.nilIfEmpty ?? "intergalactic-media"
    )

    do {
      let shareDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("InterGalacticShare", isDirectory: true)
      try FileManager.default.createDirectory(
        at: shareDirectory,
        withIntermediateDirectories: true
      )
      let fileUrl = shareDirectory.appendingPathComponent(fileName)
      try typedData.data.write(to: fileUrl, options: [.atomic])
      presentShareSheet(fileUrl: fileUrl, result: result)
    } catch {
      result(FlutterError(code: "share_file_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func presentShareSheet(fileUrl: URL, result: @escaping FlutterResult) {
    guard let controller = window?.rootViewController else {
      result(FlutterError(code: "share_unavailable", message: "No active view controller is available.", details: nil))
      return
    }

    let activityController = UIActivityViewController(
      activityItems: [fileUrl],
      applicationActivities: nil
    )
    if let popover = activityController.popoverPresentationController {
      popover.sourceView = controller.view
      popover.sourceRect = CGRect(
        x: controller.view.bounds.midX,
        y: controller.view.bounds.midY,
        width: 1,
        height: 1
      )
      popover.permittedArrowDirections = []
    }

    controller.present(activityController, animated: true) {
      result(true)
    }
  }

  private func sanitizeShareFileName(_ fileName: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    let sanitized = fileName.map { character -> Character in
      guard let scalar = String(character).unicodeScalars.first,
        allowed.contains(scalar)
      else {
        return "_"
      }
      return character
    }
    let result = String(sanitized).nilIfEmpty ?? "intergalactic-media"
    return result
  }

  private func requestMediaLibraryAuthorization(result: @escaping FlutterResult) {
    let status = MPMediaLibrary.authorizationStatus()
    guard status == .notDetermined else {
      result(mediaLibraryAuthorizationStatusString(status))
      return
    }

    MPMediaLibrary.requestAuthorization { [weak self] status in
      DispatchQueue.main.async {
        guard let self = self else {
          result("unknown")
          return
        }
        result(self.mediaLibraryAuthorizationStatusString(status))
      }
    }
  }

  private func localMediaSnapshot() -> [String: Any] {
    let player = MPMusicPlayerController.systemMusicPlayer
    let item = player.nowPlayingItem
    var snapshot: [String: Any] = [
      "supported": true,
      "state": mediaPlaybackStateString(player.playbackState),
      "authorization_status": mediaLibraryAuthorizationStatusString(
        MPMediaLibrary.authorizationStatus()
      ),
    ]

    if let title = item?.title?.nilIfEmpty {
      snapshot["title"] = title
    }
    if let artist = item?.artist?.nilIfEmpty {
      snapshot["artist"] = artist
    }
    if let album = item?.albumTitle?.nilIfEmpty {
      snapshot["album"] = album
    }
    if let duration = item?.playbackDuration, duration > 0 {
      snapshot["duration_ms"] = Int(duration * 1000)
    }
    if let artwork = item?.artwork,
       let image = artwork.image(at: CGSize(width: 96, height: 96)),
       let data = image.pngData() {
      snapshot["artwork_url"] = "data:image/png;base64,\(data.base64EncodedString())"
    }

    return snapshot
  }

  private func mediaPlaybackStateString(_ state: MPMusicPlaybackState) -> String {
    switch state {
    case .stopped:
      return "stopped"
    case .playing:
      return "playing"
    case .paused:
      return "paused"
    case .interrupted:
      return "interrupted"
    case .seekingForward:
      return "seeking_forward"
    case .seekingBackward:
      return "seeking_backward"
    @unknown default:
      return "unknown"
    }
  }

  private func mediaLibraryAuthorizationStatusString(_ status: MPMediaLibraryAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .notDetermined:
      return "not_determined"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
  }

  private func handleBiometricAvailability(result: @escaping FlutterResult) {
    let context = LAContext()
    var error: NSError?
    let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

    result([
      "available": available,
      "biometryType": biometryTypeString(context.biometryType),
    ])
  }

  private func handleBiometricAuthentication(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let reason = (arguments?["reason"] as? String)?.nilIfEmpty ?? "Authenticate with Face ID"

    let context = LAContext()
    context.localizedFallbackTitle = ""

    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      result(false)
      return
    }

    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
      DispatchQueue.main.async {
        result(success)
      }
    }
  }

  private func handleSecureRecoveryKeyStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let accountKey = secureRecoveryKeyAccountKey(from: call) else {
      result(FlutterError(code: "invalid_arguments", message: "Missing recovery-key account scope.", details: nil))
      return
    }

    let context = LAContext()
    var error: NSError?
    let biometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

    var query = secureRecoveryKeyBaseQuery(accountKey: accountKey)
    query[kSecReturnAttributes as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    let stored = secureRecoveryKeyStatusMeansStored(status)
    var response: [String: Any] = [
      "supported": true,
      "biometricAvailable": biometricAvailable,
      "biometryType": biometryTypeString(context.biometryType),
      "stored": stored,
    ]

    if !biometricAvailable {
      response["unavailableReason"] = "biometrics_unavailable"
    } else if status == errSecItemNotFound {
      response["unavailableReason"] = "not_stored"
    } else if secureRecoveryKeyStatusMeansBiometryInvalid(status) {
      response["unavailableReason"] = "biometry_changed_or_unavailable"
    } else if status != errSecSuccess && status != errSecInteractionNotAllowed {
      response["unavailableReason"] = "keychain_\(status)"
    } else if stored,
      let attributes = item as? [String: Any],
      let unreadableReason = secureRecoveryKeyUnreadableStatusReason(
        accountKey: accountKey,
        attributes: attributes,
        currentBiometryDomainState: context.evaluatedPolicyDomainState
      ) {
      response["unavailableReason"] = unreadableReason
    }

    if let attributes = item as? [String: Any],
       let modificationDate = attributes[kSecAttrModificationDate as String] as? Date {
      response["lastUpdatedAt"] = ISO8601DateFormatter().string(from: modificationDate)
    }

    result(response)
  }

  private func handleSecureRecoveryKeyWrite(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let accountKey = secureRecoveryKeyAccountKey(from: call),
      let recoveryKey = (call.arguments as? [String: Any])?["recoveryKey"] as? String,
      recoveryKey.nilIfEmpty != nil
    else {
      result(FlutterError(code: "invalid_arguments", message: "Missing recovery-key write arguments.", details: nil))
      return
    }

    let context = LAContext()
    context.localizedFallbackTitle = ""
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      result(FlutterError(code: "biometrics_unavailable", message: "Face ID or Touch ID is not available.", details: nil))
      return
    }

    context.evaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      localizedReason: "Allow Inter Galactic to store your recovery key on this device."
    ) { [weak self] success, authError in
      DispatchQueue.main.async {
        guard let self = self else {
          result(FlutterError(code: "secure_recovery_key_unavailable", message: "Secure recovery-key bridge unavailable.", details: nil))
          return
        }

        guard success else {
          result(self.secureRecoveryKeyAuthError(authError))
          return
        }

        self.storeSecureRecoveryKey(
          accountKey: accountKey,
          recoveryKey: recoveryKey,
          biometryDomainState: context.evaluatedPolicyDomainState,
          result: result
        )
      }
    }
  }

  private func handleSecureRecoveryKeyRead(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let accountKey = secureRecoveryKeyAccountKey(from: call) else {
      result(FlutterError(code: "invalid_arguments", message: "Missing recovery-key account scope.", details: nil))
      return
    }

    let arguments = call.arguments as? [String: Any]
    let reason = (arguments?["reason"] as? String)?.nilIfEmpty ?? "Unlock your stored recovery key."

    let context = LAContext()
    context.localizedFallbackTitle = ""
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      result(FlutterError(code: "biometry_changed_or_unavailable", message: "Face ID or Touch ID is not available for this stored key.", details: nil))
      return
    }

    var query = secureRecoveryKeyBaseQuery(accountKey: accountKey)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    query[kSecUseOperationPrompt as String] = reason

    DispatchQueue.global(qos: .userInitiated).async {
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      DispatchQueue.main.async {
        guard status == errSecSuccess else {
          result(self.secureRecoveryKeychainError(status))
          return
        }

        guard let data = item as? Data,
          let recoveryKey = String(data: data, encoding: .utf8),
          recoveryKey.nilIfEmpty != nil
        else {
          result(FlutterError(code: "invalid_secret_data", message: "The stored recovery key could not be decoded.", details: nil))
          return
        }

        result(recoveryKey)
      }
    }
  }

  private func handleSecureRecoveryKeyDelete(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let accountKey = secureRecoveryKeyAccountKey(from: call) else {
      result(FlutterError(code: "invalid_arguments", message: "Missing recovery-key account scope.", details: nil))
      return
    }

    let status = SecItemDelete(secureRecoveryKeyBaseQuery(accountKey: accountKey) as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      result(true)
    } else {
      result(secureRecoveryKeychainError(status))
    }
  }

  private func storeSecureRecoveryKey(
    accountKey: String,
    recoveryKey: String,
    biometryDomainState: Data?,
    result: @escaping FlutterResult
  ) {
    guard let data = recoveryKey.data(using: .utf8) else {
      result(FlutterError(code: "invalid_secret_data", message: "The recovery key could not be encoded.", details: nil))
      return
    }

    var accessControlError: Unmanaged<CFError>?
    guard let accessControl = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      .biometryCurrentSet,
      &accessControlError
    ) else {
      result(FlutterError(code: "access_control_unavailable", message: "Biometric Keychain access control is unavailable.", details: nil))
      return
    }

    var query = secureRecoveryKeyBaseQuery(accountKey: accountKey)
    query[kSecValueData as String] = data
    query[kSecAttrAccessControl as String] = accessControl
    if let biometryDomainState = biometryDomainState {
      query[kSecAttrGeneric as String] = biometryDomainState
    }

    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecSuccess {
      result(true)
    } else if status == errSecDuplicateItem {
      var updateAttributes: [String: Any] = [
        kSecValueData as String: data,
      ]
      if let biometryDomainState = biometryDomainState {
        updateAttributes[kSecAttrGeneric as String] = biometryDomainState
      }
      let updateStatus = SecItemUpdate(
        secureRecoveryKeyBaseQuery(accountKey: accountKey) as CFDictionary,
        updateAttributes as CFDictionary
      )
      if updateStatus == errSecSuccess {
        result(true)
      } else {
        result(secureRecoveryKeychainError(updateStatus))
      }
    } else {
      result(secureRecoveryKeychainError(status))
    }
  }

  private func secureRecoveryKeyAccountKey(from call: FlutterMethodCall) -> String? {
    let arguments = call.arguments as? [String: Any]
    return (arguments?["accountKey"] as? String)?.nilIfEmpty
  }

  private func secureRecoveryKeyBaseQuery(accountKey: String) -> [String: Any] {
    var query = secureRecoveryKeyServiceQuery()
    query[kSecClass as String] = kSecClassGenericPassword
    query[kSecAttrAccount as String] = accountKey
    return query
  }

  private func secureRecoveryKeyServiceQuery() -> [String: Any] {
    return [
      kSecAttrService as String: secureRecoveryKeyService,
      kSecAttrSynchronizable as String: kCFBooleanFalse!,
    ]
  }

  private func secureRecoveryKeyStatusMeansStored(_ status: OSStatus) -> Bool {
    switch status {
    case errSecSuccess, errSecInteractionNotAllowed, errSecAuthFailed, errSecDecode:
      return true
    default:
      return false
    }
  }

  private func secureRecoveryKeyStatusMeansBiometryInvalid(_ status: OSStatus) -> Bool {
    return status == errSecAuthFailed || status == errSecDecode
  }

  private func secureRecoveryKeyUnreadableStatusReason(
    accountKey: String,
    attributes: [String: Any],
    currentBiometryDomainState: Data?
  ) -> String? {
    if let storedDomainState = attributes[kSecAttrGeneric as String] as? Data,
      !storedDomainState.isEmpty,
      let currentBiometryDomainState = currentBiometryDomainState,
      storedDomainState != currentBiometryDomainState {
      return "biometry_changed_or_unavailable"
    }

    var query = secureRecoveryKeyBaseQuery(accountKey: accountKey)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess, errSecInteractionNotAllowed:
      return nil
    case errSecItemNotFound, errSecAuthFailed, errSecDecode:
      return "biometry_changed_or_unavailable"
    default:
      return "keychain_\(status)"
    }
  }

  private func secureRecoveryKeyAuthError(_ error: Error?) -> FlutterError {
    let nsError = error.map { $0 as NSError }
    let code: String
    if nsError?.code == LAError.userCancel.rawValue ||
      nsError?.code == LAError.systemCancel.rawValue ||
      nsError?.code == LAError.appCancel.rawValue {
      code = "auth_cancelled"
    } else {
      code = "auth_failed"
    }

    return FlutterError(code: code, message: "Biometric authentication did not complete.", details: nil)
  }

  private func secureRecoveryKeychainError(_ status: OSStatus) -> FlutterError {
    let code: String
    switch status {
    case errSecItemNotFound:
      code = "not_found"
    case errSecUserCanceled:
      code = "auth_cancelled"
    case errSecAuthFailed:
      code = "auth_failed"
    case errSecInteractionNotAllowed, errSecDecode:
      code = "biometry_changed_or_unavailable"
    default:
      code = "keychain_error"
    }

    return FlutterError(code: code, message: "Secure recovery-key Keychain operation failed.", details: status)
  }

  private func configureNotificationsChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: notificationsChannelName, binaryMessenger: binaryMessenger)
    notificationsChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "notifications_unavailable", message: "Notification bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "getPermissionStatus":
        self.handleNotificationPermissionStatus(result: result)
      case "requestPermissions":
        self.handleNotificationPermissionRequest(result: result)
      case "registerForRemoteNotifications":
        self.registerForRemoteNotificationsIfAuthorized(result: result)
      case "getPushToken":
        result(self.pushTokenHex)
      case "getApnsEnvironment":
        result(self.currentApnsEnvironment())
      case "takePendingNotificationResponse":
        // The HEAD, not the whole queue: Dart handles and acknowledges one
        // response at a time and re-drains afterwards, so handing it the
        // oldest unacknowledged one keeps the order the user acted in.
        result(self.pendingNotificationResponses.first)
      case "acknowledgeNotificationResponse":
        self.handleNotificationResponseAcknowledgement(call: call, result: result)
      case "protectNotificationPreviewFile":
        self.handleNotificationPreviewFileProtection(call: call, result: result)
      case "debugReplayNotificationResponse":
        #if DEBUG || IOS_NOTIFICATION_DEBUG_HARNESS
        self.handleDebugReplayNotificationResponse(call: call, result: result)
        #else
        result(FlutterMethodNotImplemented)
        #endif
      case "debugReplayLastNotificationResponse":
        #if DEBUG || IOS_NOTIFICATION_DEBUG_HARNESS
        self.handleDebugReplayLastNotificationResponse(result: result)
        #else
        result(FlutterMethodNotImplemented)
        #endif
      case "debugGetLastNotificationUserInfo":
        #if DEBUG || IOS_NOTIFICATION_DEBUG_HARNESS
        result(self.lastNotificationUserInfo)
        #else
        result(FlutterMethodNotImplemented)
        #endif
      case "openAppSettings":
        self.openAppSettings(result: result)
      case "setBadgeCount":
        self.handleSetBadgeCount(call: call, result: result)
      case "deliveredRemoteEventIds":
        self.handleDeliveredRemoteEventIds(result: result)
      case "takePendingRemoteWake":
        self.handleTakePendingRemoteWake(result: result)
      case "remoteWakeElapsed":
        self.handleRemoteWakeElapsed(call: call, result: result)
      case "completeRemoteWake":
        self.handleCompleteRemoteWake(call: call, result: result)
      case "removeDeliveredRemoteNotification":
        self.handleRemoveDeliveredRemoteNotification(call: call, result: result)
      case "removeDeliveredRemoteNotificationsForRoom":
        self.handleRemoveDeliveredRemoteNotificationsForRoom(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureStoryVideoExportChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: storyVideoExportChannelName,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "story_video_export_unavailable", message: "Story video export bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "exportTrim":
        self.handleStoryVideoExport(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleStoryVideoExport(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let sourcePath = arguments["sourcePath"] as? String,
      let trimStartMs = storyVideoExportInt(arguments["trimStartMs"]),
      let trimEndMs = storyVideoExportInt(arguments["trimEndMs"]),
      !sourcePath.isEmpty,
      trimStartMs >= 0,
      trimEndMs > trimStartMs
    else {
      result(FlutterError(code: "invalid_arguments", message: "Invalid story video trim arguments.", details: nil))
      return
    }

    let sourceUrl = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: sourceUrl.path) else {
      result(FlutterError(code: "invalid_arguments", message: "Story video source file does not exist.", details: nil))
      return
    }

    let sourceName = (arguments["sourceName"] as? String)?.nilIfEmpty ?? sourceUrl.lastPathComponent
    let outputDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("intergalactic_story_video_exports", isDirectory: true)

    do {
      try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      result(FlutterError(code: "story_video_export_failed", message: error.localizedDescription, details: nil))
      return
    }

    let outputName = storyVideoTrimmedName(sourceName)
    let outputUrl = outputDirectory.appendingPathComponent(outputName)
    try? FileManager.default.removeItem(at: outputUrl)

    let asset = AVURLAsset(url: sourceUrl)
    let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
    let preset: String
    if compatiblePresets.contains(AVAssetExportPresetMediumQuality) {
      preset = AVAssetExportPresetMediumQuality
    } else if compatiblePresets.contains(AVAssetExportPresetHighestQuality) {
      preset = AVAssetExportPresetHighestQuality
    } else if compatiblePresets.contains(AVAssetExportPresetPassthrough) {
      preset = AVAssetExportPresetPassthrough
    } else {
      result(FlutterError(code: "story_video_export_unsupported", message: "Story video export is not supported for this media.", details: nil))
      return
    }

    guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
      result(FlutterError(code: "story_video_export_unsupported", message: "Story video export could not be started.", details: nil))
      return
    }
    guard exportSession.supportedFileTypes.contains(.mp4) else {
      result(FlutterError(code: "story_video_export_unsupported", message: "MP4 story video export is not supported for this media.", details: nil))
      return
    }

    let start = CMTime(
      seconds: Double(trimStartMs) / 1000.0,
      preferredTimescale: 600
    )
    var end = CMTime(
      seconds: Double(trimEndMs) / 1000.0,
      preferredTimescale: 600
    )
    if CMTimeCompare(end, asset.duration) > 0 {
      end = asset.duration
    }
    guard CMTimeCompare(end, start) > 0 else {
      result(FlutterError(code: "invalid_arguments", message: "Invalid story video trim range.", details: nil))
      return
    }

    exportSession.outputURL = outputUrl
    exportSession.outputFileType = .mp4
    exportSession.timeRange = CMTimeRange(
      start: start,
      duration: CMTimeSubtract(end, start)
    )
    exportSession.shouldOptimizeForNetworkUse = true

    exportSession.exportAsynchronously {
      DispatchQueue.main.async {
        switch exportSession.status {
        case .completed:
          let attributes = try? FileManager.default.attributesOfItem(atPath: outputUrl.path)
          let fileSize = attributes?[.size] as? NSNumber
          guard FileManager.default.fileExists(atPath: outputUrl.path),
            (fileSize?.intValue ?? 0) > 0
          else {
            try? FileManager.default.removeItem(at: outputUrl)
            result(FlutterError(code: "story_video_export_failed", message: "Story video trim export was empty.", details: nil))
            return
          }
          result([
            "path": outputUrl.path,
            "name": outputName,
            "mime_type": "video/mp4",
            "size": fileSize?.intValue ?? 0,
          ])
        case .cancelled:
          try? FileManager.default.removeItem(at: outputUrl)
          result(FlutterError(code: "story_video_export_failed", message: "Story video trim export was cancelled.", details: nil))
        default:
          try? FileManager.default.removeItem(at: outputUrl)
          result(FlutterError(code: "story_video_export_failed", message: exportSession.error?.localizedDescription ?? "Story video trim export failed.", details: nil))
        }
      }
    }
  }

  private func storyVideoExportInt(_ value: Any?) -> Int? {
    if let int = value as? Int {
      return int
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let string = value as? String {
      return Int(string)
    }
    return nil
  }

  private func storyVideoTrimmedName(_ sourceName: String) -> String {
    let baseName = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    let sanitized = baseName.map { character -> Character in
      guard let scalar = String(character).unicodeScalars.first,
        allowed.contains(scalar)
      else {
        return "_"
      }
      return character
    }
    let safeBase = String(sanitized).nilIfEmpty ?? "story-video"
    return "\(safeBase)-trim-\(Int(Date().timeIntervalSince1970 * 1000)).mp4"
  }

  private func configureVoiceRecorderChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: voiceRecorderChannelName,
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "voice_recorder_unavailable", message: "Voice recorder bridge unavailable.", details: nil))
        return
      }

      switch call.method {
      case "startRecording":
        self.handleVoiceRecordingStart(result: result)
      case "stopRecording":
        self.handleVoiceRecordingStop(result: result)
      case "cancelRecording":
        self.handleVoiceRecordingCancel(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleVoiceRecordingStart(result: @escaping FlutterResult) {
    if voiceRecorder?.isRecording == true {
      result(FlutterError(code: "voice_recorder_active", message: "A voice recording is already active.", details: nil))
      return
    }

    requestVoiceRecordingPermission { [weak self] granted in
      DispatchQueue.main.async {
        guard let self = self else {
          result(FlutterError(code: "voice_recorder_unavailable", message: "Voice recorder bridge unavailable.", details: nil))
          return
        }

        guard granted else {
          result(FlutterError(code: "microphone_permission_denied", message: "Microphone permission was denied.", details: nil))
          return
        }

        do {
          let audioSession = AVAudioSession.sharedInstance()
          try audioSession.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetooth]
          )
          try audioSession.setActive(true)

          let fileName = "voice-message-\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
          let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
          let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 64000,
          ]
          let recorder = try AVAudioRecorder(url: url, settings: settings)
          recorder.isMeteringEnabled = true

          guard recorder.record() else {
            result(FlutterError(code: "voice_recorder_start_failed", message: "The microphone recorder could not be started.", details: nil))
            return
          }

          self.voiceRecorder = recorder
          self.voiceRecorderUrl = url
          result([
            "path": url.path,
            "name": fileName,
            "mime_type": "audio/mp4",
          ])
        } catch {
          result(FlutterError(code: "voice_recorder_start_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func handleVoiceRecordingStop(result: @escaping FlutterResult) {
    guard let recorder = voiceRecorder, let url = voiceRecorderUrl else {
      result(FlutterError(code: "voice_recorder_inactive", message: "No voice recording is active.", details: nil))
      return
    }

    let durationMs = max(0, Int(recorder.currentTime * 1000))
    recorder.stop()
    voiceRecorder = nil
    voiceRecorderUrl = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

    let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    let fileSize = fileAttributes?[.size] as? NSNumber
    result([
      "path": url.path,
      "name": url.lastPathComponent,
      "mime_type": "audio/mp4",
      "size": fileSize?.intValue ?? 0,
      "duration_ms": durationMs,
    ])
  }

  private func handleVoiceRecordingCancel(result: @escaping FlutterResult) {
    let url = voiceRecorderUrl
    voiceRecorder?.stop()
    voiceRecorder = nil
    voiceRecorderUrl = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

    if let url {
      try? FileManager.default.removeItem(at: url)
    }

    result(true)
  }

  private func requestVoiceRecordingPermission(completion: @escaping (Bool) -> Void) {
    let audioSession = AVAudioSession.sharedInstance()
    switch audioSession.recordPermission {
    case .granted:
      completion(true)
    case .denied:
      completion(false)
    case .undetermined:
      audioSession.requestRecordPermission { granted in
        completion(granted)
      }
    @unknown default:
      completion(false)
    }
  }

  private func handleNotificationPermissionStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        result(self.authorizationStatusString(settings.authorizationStatus))
      }
    }
  }

  private func registerForRemoteNotificationsIfAuthorized(result: FlutterResult?) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let canRegister = self.canRegisterForRemoteNotifications(settings.authorizationStatus)

      // BUG-179: this is the eligibility gate. When it returns false the app
      // never calls registerForRemoteNotifications, never gets a token, and
      // never reports anything - which looks identical to "APNs stopped
      // delivering" from the outside. Log the decision and the status that
      // produced it so a device log can tell those two apart.
      NSLog(
        "intergalactic_ios_push event=register_eligibility status=%@ can_register=%@ has_token=%@",
        self.authorizationStatusString(settings.authorizationStatus),
        String(canRegister),
        String(self.pushTokenHex != nil)
      )

      DispatchQueue.main.async {
        if canRegister {
          NSLog("intergalactic_ios_push event=register_requested")
          UIApplication.shared.registerForRemoteNotifications()
        }

        result?(canRegister)
      }
    }
  }

  private func handleNotificationPermissionRequest(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
      NSLog(
        "intergalactic_ios_push event=authorization_result granted=%@ error=%@",
        String(granted),
        error?.localizedDescription ?? "none"
      )
      DispatchQueue.main.async {
        if granted {
          NSLog("intergalactic_ios_push event=register_requested source=authorization_granted")
          UIApplication.shared.registerForRemoteNotifications()
        }
        result(granted)
      }
    }
  }

  private func openAppSettings(result: @escaping FlutterResult) {
    guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }

    UIApplication.shared.open(settingsUrl, options: [:]) { success in
      result(success)
    }
  }

  private func handleSetBadgeCount(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let count = arguments?["count"] as? Int ?? 0
    let sanitizedCount = max(0, count)

    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(sanitizedCount) { error in
        DispatchQueue.main.async {
          if let error {
            result(
              FlutterError(
                code: "badge_update_failed",
                message: error.localizedDescription,
                details: sanitizedCount
              )
            )
          } else {
            result(true)
          }
        }
      }
      return
    }

    UIApplication.shared.applicationIconBadgeNumber = sanitizedCount
    result(true)
  }

  private func captureNotificationResponse(_ response: UNNotificationResponse) -> Bool {
    let input = (response as? UNTextInputNotificationResponse)?.userText
    return captureNotificationUserInfo(
      response.notification.request.content.userInfo,
      actionIdentifier: response.actionIdentifier,
      input: input,
      source: "apns-response"
    )
  }

  @discardableResult
  private func captureNotificationUserInfo(
    _ userInfo: [AnyHashable: Any],
    actionIdentifier: String?,
    input: String? = nil,
    source: String = "apns"
  ) -> Bool {
    let normalizedUserInfo = notificationDictionary(userInfo)
    if let normalizedUserInfo {
      lastNotificationUserInfo = normalizedUserInfo
    }
    let roomId = notificationString(userInfo, keys: ["room_id", "roomId", "roomID"])
    let routePayload = notificationString(
      userInfo,
      keys: ["payload", "route_payload", "routePayload", "deep_link", "deepLink", "url"]
    )
    NSLog(
      "intergalactic_ios_notification_payload_received source=%@ room_present=%@ route_payload_present=%@",
      source,
      roomId == nil ? "false" : "true",
      routePayload == nil ? "false" : "true"
    )
    if roomId == nil && routePayload == nil {
      return false
    }

    var payload: [String: Any] = [
      "response_id": UUID().uuidString,
      "action_id": actionIdentifier ?? UNNotificationDefaultActionIdentifier,
      "source": source,
    ]

    if let normalizedUserInfo {
      payload["userInfo"] = normalizedUserInfo
    }
    if let roomId {
      payload["room_id"] = roomId
    }
    if let clientId = notificationString(userInfo, keys: ["client_id", "clientId", "clientID"]) {
      payload["client_id"] = clientId
    }
    if let eventId = notificationString(userInfo, keys: ["event_id", "eventId", "eventID"]) {
      payload["event_id"] = eventId
    }
    if let roomName = notificationString(userInfo, keys: ["room_name", "roomName"]) {
      payload["room_name"] = roomName
    }
    if let routePayload {
      payload["payload"] = routePayload
    }
    if let input {
      // Typed notification input is required only until Dart acknowledges this
      // response. It is never logged or copied into debug payload storage.
      payload["input"] = input
    }

    if pendingNotificationResponses.count >= Self.maxPendingNotificationResponses {
      // Drop the OLDEST: it has been queued longest, so its background
      // assertion is the closest to expiring, while the newest is the action
      // the user just took. Logged because a dropped response is a lost reply.
      let dropped = pendingNotificationResponses.removeFirst()
      NSLog(
        "intergalactic_ios_notification_response_dropped reason=queue_full response_id_present=%@",
        dropped["response_id"] == nil ? "false" : "true"
      )
      // And end its assertion here, because nothing else can. The two stores
      // are keyed alike and an entry normally leaves BOTH on acknowledgement -
      // but Dart acknowledges what it was delivered, and this payload is now
      // gone, so no acknowledgement for it will ever arrive. Without this the
      // task sits in `notificationResponseTasks` holding its APNs completion
      // handler until iOS expires it: the reply is lost either way, but the
      // app also stays awake for nothing and the handler is called late by the
      // expiration path rather than promptly here.
      if let droppedId = dropped["response_id"] as? String {
        endNotificationResponseTask(responseId: droppedId, reason: "queue_full")
      }
    }
    pendingNotificationResponses.append(payload)
    DispatchQueue.main.async { [weak self] in
      self?.deliverPendingNotificationResponse()
    }
    return true
  }

  private func handleNotificationPreviewFileProtection(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String
    else {
      result(false)
      return
    }

    // The Dart side writes previews under getTemporaryDirectory(). On Apple
    // platforms path_provider maps that to the CACHES directory, not to
    // NSTemporaryDirectory() -- PathProviderPlugin.swift returns
    // `.cachesDirectory` for `case .temp`. Checking only NSTemporaryDirectory()
    // therefore rejected every real preview: the file was written to
    // Library/Caches/intergalactic-notification-previews, failed the prefix
    // guard, and the Dart caller deleted it and returned no attachment. The
    // notification still displayed with its "Sent an image" text, so the only
    // symptom was a permanently missing image preview.
    //
    // Accept either root. Both are app-container-private, and keeping the
    // containment guard is the point: this method sets a file-protection
    // attribute on a caller-supplied path, so it must never accept an arbitrary
    // one.
    // Containment compares RESOLVED paths on both sides (S&C 2026-09-05):
    // `standardizedFileURL` folds `.` and `..` but leaves symlinks alone, so
    // a link inside the preview directory pointing outside it would have
    // passed the prefix check and had its target's attribute changed.
    // `resolvingSymlinksInPath` follows links on the root (the caches
    // directory is itself reached through `/private` on device) and on the
    // candidate, so the comparison is between the real locations. A missing
    // candidate still fails: it resolves to itself and then fails the
    // existence check, as before.
    let previewDirectoryName = "intergalactic-notification-previews"
    let allowedRoots =
      ([NSTemporaryDirectory()]
      + NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true))
      .map {
        URL(fileURLWithPath: $0, isDirectory: true)
          .appendingPathComponent(previewDirectoryName, isDirectory: true)
          .standardizedFileURL.resolvingSymlinksInPath().path + "/"
      }
    let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    guard allowedRoots.contains(where: { candidate.path.hasPrefix($0) }),
      FileManager.default.fileExists(atPath: candidate.path)
    else {
      result(false)
      return
    }

    do {
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: candidate.path
      )
      result(true)
    } catch {
      result(false)
    }
  }

  private func deliverPendingNotificationResponse() {
    if pendingNotificationResponses.isEmpty {
      return
    }
    guard let notificationsChannel else {
      NSLog(
        // %ld, not %d, for the same reason recorded at the token log above:
        // `count` is a Swift Int and 64-bit on every device this ships to,
        // while %d reads 32. This log is read when notifications are already
        // behaving inexplicably, so a number that depends on endianness is the
        // last thing it should carry.
        "intergalactic_ios_notification_response_delivery_deferred reason=channel_not_ready pending=%ld",
        pendingNotificationResponses.count
      )
      return
    }

    // Every queued response is delivered, not just the head. Each carries its
    // own response id and is acknowledged independently, so Dart can act on
    // them in any order; delivering only the head would leave the rest waiting
    // on the next become-active for no reason. The queue is not cleared here -
    // an entry leaves it only on acknowledgement, which is what makes a
    // delivery that Dart never processes recoverable.
    for payload in pendingNotificationResponses {
      NSLog(
        "intergalactic_ios_notification_response_delivered response_id_present=%@",
        payload["response_id"] == nil ? "false" : "true"
      )
      notificationsChannel.invokeMethod("notificationResponseReceived", arguments: payload)
    }
  }

  private func handleNotificationResponseAcknowledgement(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let responseId = arguments["response_id"] as? String
    else {
      result(false)
      return
    }

    // End the assertion regardless of whether a queued payload still matches.
    // It is keyed independently of the payload store so it cannot be stranded -
    // originally because a single slot could be overwritten, and now because a
    // queued payload can be evicted at the cap. Either way the assertion must
    // not depend on the payload still being findable.
    //
    // (This said "the single-slot payload" until 2026-08-18. There is no single
    // slot any more, and a reader checking whether the hazard still applied
    // would have concluded it did not.)
    endNotificationResponseTask(responseId: responseId, reason: "acknowledged")

    if let index = pendingNotificationResponses.firstIndex(where: {
      $0["response_id"] as? String == responseId
    }) {
      // Removed BY ID rather than by clearing the store, so acknowledging the
      // second of two queued responses cannot discard the first.
      pendingNotificationResponses.remove(at: index)
      NSLog("intergalactic_ios_notification_response_acknowledged")
      result(true)
      return
    }

    result(false)
  }

  // MARK: - Background execution assertions

  /// One `beginBackgroundTask` assertion, keyed by an opaque token.
  ///
  /// The general primitive. It was extracted from the notification-response
  /// path below, which is now one consumer of it; the database release
  /// trigger (B5) is the other, through the `background_assertion` channel.
  /// Both need the same bounded window of execution after the app is
  /// backgrounded, and one registry means the two cannot drift apart in how
  /// they begin, end, or expire.
  private struct BackgroundAssertion {
    let identifier: UIBackgroundTaskIdentifier
    let name: String
    /// Called when iOS reclaims the time, BEFORE the assertion is ended, so a
    /// consumer can finish its own bookkeeping.
    let onExpired: (() -> Void)?
  }

  private var backgroundAssertions: [String: BackgroundAssertion] = [:]

  /// Returns the token, or nil when iOS declined (`.invalid`). A declined
  /// assertion is a normal outcome the caller must handle by proceeding
  /// without one, not an error.
  private func beginBackgroundAssertion(
    name: String,
    onExpired: (() -> Void)? = nil
  ) -> String? {
    let token = UUID().uuidString
    var identifier = UIBackgroundTaskIdentifier.invalid
    identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      self?.expireBackgroundAssertion(token: token)
    }

    guard identifier != .invalid else {
      NSLog("intergalactic_ios_background_assertion result=unavailable name=%@", name)
      return nil
    }

    backgroundAssertions[token] = BackgroundAssertion(
      identifier: identifier,
      name: name,
      onExpired: onExpired
    )
    NSLog("intergalactic_ios_background_assertion result=began name=%@", name)
    return token
  }

  private func endBackgroundAssertion(token: String, reason: String) {
    guard let assertion = backgroundAssertions.removeValue(forKey: token) else {
      return
    }

    NSLog(
      "intergalactic_ios_background_assertion result=ended name=%@ reason=%@",
      assertion.name,
      reason
    )
    UIApplication.shared.endBackgroundTask(assertion.identifier)
  }

  private func expireBackgroundAssertion(token: String) {
    guard let assertion = backgroundAssertions[token] else {
      return
    }
    // The consumer's handler may end the assertion itself (the notification
    // path does, through its own end routine). Ending again afterwards is a
    // no-op because the entry is already gone.
    assertion.onExpired?()
    endBackgroundAssertion(token: token, reason: "expired")
  }

  private func configureBackgroundAssertionChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: backgroundAssertionChannelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(
          code: "background_assertion_unavailable",
          message: "Background assertion bridge unavailable.",
          details: nil
        ))
        return
      }

      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "begin":
        let name = arguments?["name"] as? String ?? "intergalactic.background-work"
        result(self.beginBackgroundAssertion(name: name))
      case "end":
        guard let token = arguments?["token"] as? String, !token.isEmpty else {
          result(FlutterError(
            code: "background_assertion_bad_token",
            message: "A background assertion token is required to end it.",
            details: nil
          ))
          return
        }
        self.endBackgroundAssertion(token: token, reason: "ended")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Notification response background assertion

  private struct NotificationResponseTask {
    let assertionToken: String
    let completionHandler: () -> Void
  }

  /// Keyed by response id, NOT a single slot.
  ///
  /// This was keyed independently while the payload store was still one
  /// optional, precisely so an overwritten payload could not strand an
  /// assertion. `pendingNotificationResponses` is now a queue keyed the same
  /// way, so the two agree: an entry in either is removed by response id, and
  /// the acknowledgement is a safe end condition for both.
  ///
  /// The assertion itself lives in the general registry above; this map only
  /// pairs it with the completion handler iOS is waiting on.
  private var notificationResponseTasks: [String: NotificationResponseTask] = [:]

  private func beginNotificationResponseTask(
    responseId: String?,
    completionHandler: @escaping () -> Void
  ) {
    guard let responseId, !responseId.isEmpty else {
      // Nothing to key an assertion to, so nothing can end it deterministically.
      // Complete immediately rather than hold one we cannot release.
      completionHandler()
      return
    }

    // A response id arriving twice would strand the first assertion.
    endNotificationResponseTask(responseId: responseId, reason: "superseded")

    let token = beginBackgroundAssertion(
      name: "intergalactic.notification-response"
    ) { [weak self] in
      // iOS is reclaiming the time. Deliver the completion handler and drop the
      // assertion; the reply itself falls back to the resume drain, which is
      // today's behaviour rather than a regression.
      self?.endNotificationResponseTask(responseId: responseId, reason: "expired")
    }

    guard let token else {
      NSLog("intergalactic_ios_notification_response_task result=unavailable")
      completionHandler()
      return
    }

    notificationResponseTasks[responseId] = NotificationResponseTask(
      assertionToken: token,
      completionHandler: completionHandler
    )
    NSLog("intergalactic_ios_notification_response_task result=began")
  }

  private func endNotificationResponseTask(responseId: String, reason: String) {
    guard let task = notificationResponseTasks.removeValue(forKey: responseId) else {
      return
    }

    NSLog(
      "intergalactic_ios_notification_response_task result=ended reason=%@",
      reason
    )
    // Order matters: tell iOS the work is done, then release the assertion.
    task.completionHandler()
    endBackgroundAssertion(token: task.assertionToken, reason: reason)
  }

  #if DEBUG || IOS_NOTIFICATION_DEBUG_HARNESS
  private func handleDebugReplayNotificationResponse(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    let arguments = call.arguments as? [String: Any]
    let rawPayload = arguments?["payload"] ?? call.arguments

    guard let dictionary = notificationDictionary(rawPayload) else {
      result(
        FlutterError(
          code: "invalid_debug_notification_payload",
          message: "Debug notification replay requires a JSON object or payload map.",
          details: nil
        )
      )
      return
    }

    var userInfo: [AnyHashable: Any] = [:]
    for (key, value) in dictionary {
      userInfo[key] = value
    }

    let captured = captureNotificationUserInfo(
      userInfo,
      actionIdentifier: UNNotificationDefaultActionIdentifier,
      source: "debug-replay"
    )
    result(captured)
  }

  private func handleDebugReplayLastNotificationResponse(result: @escaping FlutterResult) {
    guard let lastNotificationUserInfo else {
      result(false)
      return
    }

    var userInfo: [AnyHashable: Any] = [:]
    for (key, value) in lastNotificationUserInfo {
      userInfo[key] = value
    }

    let captured = captureNotificationUserInfo(
      userInfo,
      actionIdentifier: UNNotificationDefaultActionIdentifier,
      source: "debug-replay-last"
    )
    result(captured)
  }
  #endif

  private func notificationString(_ userInfo: [AnyHashable: Any], keys: [String]) -> String? {
    guard let dictionary = notificationDictionary(userInfo) else {
      return nil
    }

    return notificationString(dictionary, keys: keys)
  }

  private func notificationString(_ dictionary: [String: Any], keys: [String], depth: Int = 0) -> String? {
    if depth > 3 {
      return nil
    }

    for key in keys {
      if let value = notificationString(dictionary[key]) {
        return value
      }
    }

    for containerKey in [
      "notification",
      "data",
      "custom",
      "payload",
      "matrix",
      "m",
      "content",
      "userInfo",
      "aps",
    ] {
      guard let nested = notificationDictionary(dictionary[containerKey]) else {
        continue
      }

      if let value = notificationString(nested, keys: keys, depth: depth + 1) {
        return value
      }
    }

    return nil
  }

  private func notificationDictionary(_ value: Any?) -> [String: Any]? {
    if let dictionary = value as? [String: Any] {
      return dictionary
    }

    if let dictionary = value as? [AnyHashable: Any] {
      var normalized: [String: Any] = [:]
      for (key, entryValue) in dictionary {
        normalized[String(describing: key)] = entryValue
      }
      return normalized
    }

    guard let string = notificationString(value),
      let data = string.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data, options: []),
      let dictionary = object as? [String: Any]
    else {
      return nil
    }

    return dictionary
  }

  private func notificationString(_ value: Any?) -> String? {
    if let string = value as? String {
      return string.isEmpty ? nil : string
    }

    if let number = value as? NSNumber {
      return number.stringValue
    }

    return nil
  }

  private func currentApnsEnvironment() -> String? {
    if let profileEnvironment = embeddedProvisioningValue("aps-environment") {
      return profileEnvironment
    }

    return Bundle.main.object(forInfoDictionaryKey: "IGAPNSEnvironment") as? String
  }

  private func embeddedProvisioningValue(_ key: String) -> String? {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url),
      let profile = String(data: data, encoding: .isoLatin1)
    else {
      return nil
    }

    guard let keyRange = profile.range(of: "<key>\(key)</key>") else {
      return nil
    }

    let remainder = profile[keyRange.upperBound...]
    guard let valueStart = remainder.range(of: "<string>")?.upperBound,
      let valueEnd = remainder[valueStart...].range(of: "</string>")?.lowerBound
    else {
      return nil
    }

    return String(remainder[valueStart..<valueEnd])
  }

  private func canRegisterForRemoteNotifications(_ status: UNAuthorizationStatus) -> Bool {
    switch status {
    case .authorized, .ephemeral, .provisional:
      return true
    case .denied, .notDetermined:
      return false
    @unknown default:
      return false
    }
  }

  private func authorizationStatusString(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .ephemeral:
      return "ephemeral"
    case .provisional:
      return "provisional"
    case .notDetermined:
      return "not_determined"
    @unknown default:
      return "unknown"
    }
  }

  private func biometryTypeString(_ type: LABiometryType) -> String {
    switch type {
    case .faceID:
      return "face_id"
    case .touchID:
      return "touch_id"
    case .none:
      return "none"
    @unknown default:
      return "unknown"
    }
  }
}

extension AppDelegate: UINavigationControllerDelegate, UIImagePickerControllerDelegate {
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    let result = pendingCameraMediaPickerResult
    pendingCameraMediaPickerResult = nil
    picker.dismiss(animated: true) {
      result?(nil)
    }
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    guard let result = pendingCameraMediaPickerResult else {
      picker.dismiss(animated: true)
      return
    }

    pendingCameraMediaPickerResult = nil
    let payload = cameraMediaPickerPayload(from: info)
    picker.dismiss(animated: true) {
      switch payload {
      case .success(let value):
        result(value)
      case .failure(let error):
        result(
          FlutterError(
            code: "camera_media_export_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func cameraMediaPickerPayload(
    from info: [UIImagePickerController.InfoKey: Any]
  ) -> Result<[String: Any], Error> {
    let mediaType = info[.mediaType] as? String
    if mediaType == "public.movie" {
      return cameraMoviePayload(from: info)
    }

    return cameraImagePayload(from: info)
  }

  private func cameraImagePayload(
    from info: [UIImagePickerController.InfoKey: Any]
  ) -> Result<[String: Any], Error> {
    guard let image = info[.originalImage] as? UIImage,
      let data = image.jpegData(compressionQuality: 0.92)
    else {
      return .failure(CameraMediaPickerError.invalidImage)
    }

    let fileUrl = cameraMediaTemporaryDirectory()
      .appendingPathComponent("camera-\(cameraMediaTimestamp()).jpg")

    do {
      try FileManager.default.createDirectory(
        at: fileUrl.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: fileUrl, options: [.atomic])
      return .success(cameraMediaPayload(
        fileUrl: fileUrl,
        mimeType: "image/jpeg",
        size: data.count
      ))
    } catch {
      return .failure(error)
    }
  }

  private func cameraMoviePayload(
    from info: [UIImagePickerController.InfoKey: Any]
  ) -> Result<[String: Any], Error> {
    guard let sourceUrl = info[.mediaURL] as? URL else {
      return .failure(CameraMediaPickerError.invalidMovie)
    }

    let fileExtension = sourceUrl.pathExtension.nilIfEmpty ?? "mov"
    let fileUrl = cameraMediaTemporaryDirectory()
      .appendingPathComponent("camera-\(cameraMediaTimestamp()).\(fileExtension)")

    do {
      try FileManager.default.createDirectory(
        at: fileUrl.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: fileUrl.path) {
        try FileManager.default.removeItem(at: fileUrl)
      }
      try FileManager.default.copyItem(at: sourceUrl, to: fileUrl)
      let size = (try? fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      return .success(cameraMediaPayload(
        fileUrl: fileUrl,
        mimeType: cameraMovieMimeType(fileExtension: fileExtension),
        size: size
      ))
    } catch {
      return .failure(error)
    }
  }

  private func cameraMediaTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("InterGalacticCamera", isDirectory: true)
  }

  private func cameraMediaTimestamp() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
  }

  private func cameraMediaPayload(
    fileUrl: URL,
    mimeType: String,
    size: Int
  ) -> [String: Any] {
    [
      "path": fileUrl.path,
      "name": fileUrl.lastPathComponent,
      "mimeType": mimeType,
      "size": size,
    ]
  }

  private func cameraMovieMimeType(fileExtension: String) -> String {
    switch fileExtension.lowercased() {
    case "mp4", "m4v":
      return "video/mp4"
    case "mov", "qt":
      return "video/quicktime"
    default:
      return "video/\(fileExtension.lowercased())"
    }
  }

  private enum CameraMediaPickerError: LocalizedError {
    case invalidImage
    case invalidMovie

    var errorDescription: String? {
      switch self {
      case .invalidImage:
        return "The captured image could not be exported."
      case .invalidMovie:
        return "The captured video could not be exported."
      }
    }
  }
}

extension AppDelegate: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    NSLog("intergalactic_ios_call_pip event=will_start")
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    NSLog("intergalactic_ios_call_pip event=did_start")
    resolvePendingMobileCallPictureInPictureStart(true)
    notifyMobileCallPresentationChanged()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
      self?.updateMobileCallPictureInPictureSnapshot(afterScreenUpdates: true)
    }
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    NSLog(
      "intergalactic_ios_call_pip event=start_failed error=%@",
      error.localizedDescription
    )
    resolvePendingMobileCallPictureInPictureStart(false)
    clearMobileCallPictureInPictureContentState()
    mobileCallPictureInPictureController = nil
    mobileCallPictureInPictureContentViewController = nil
    notifyMobileCallPresentationChanged()
  }

  func pictureInPictureControllerWillStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    NSLog("intergalactic_ios_call_pip event=will_stop")
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    NSLog("intergalactic_ios_call_pip event=did_stop")
    resolvePendingMobileCallPictureInPictureStart(false)
    clearMobileCallPictureInPictureContentState()
    mobileCallPictureInPictureController = nil
    mobileCallPictureInPictureContentViewController = nil
    notifyMobileCallPresentationChanged()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    NSLog("intergalactic_ios_call_pip event=restore_user_interface")
    notifyMobileCallPictureInPictureAction("returnToCall")
    completionHandler(true)
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
