import Flutter
import AVFoundation
import AVKit
import LocalAuthentication
import MediaPlayer
import Photos
import Security
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appIconChannelName = "chat.intergalactic.app/app_icon"
  private let biometricsChannelName = "chat.intergalactic.app/biometrics"
  private let callAudioChannelName = "chat.intergalactic.app/call_audio"
  private let cameraMediaPickerChannelName = "chat.intergalactic.app/ios_camera_media_picker"
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
  private var pushTokenHex: String?
  private var lastNotificationUserInfo: [String: Any]?
  private var pendingNotificationResponse: [String: Any]?
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
      configureAppIconChannel(binaryMessenger: controller.binaryMessenger)
      configureBiometricsChannel(binaryMessenger: controller.binaryMessenger)
      configureCallAudioChannel(binaryMessenger: controller.binaryMessenger)
      configureCameraMediaPickerChannel(binaryMessenger: controller.binaryMessenger)
      ImageCutoutChannel.register(binaryMessenger: controller.binaryMessenger)
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

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
    let tokenChanged = tokenHex != pushTokenHex
    pushTokenHex = tokenHex
    if tokenChanged {
      notificationsChannel?.invokeMethod("pushTokenUpdated", arguments: pushTokenHex)
    }
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    if pushTokenHex == nil {
      notificationsChannel?.invokeMethod(
        "pushTokenRegistrationFailed",
        arguments: error.localizedDescription
      )
    }
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
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
      completionHandler()
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
        result(self.pendingNotificationResponse)
      case "acknowledgeNotificationResponse":
        self.handleNotificationResponseAcknowledgement(call: call, result: result)
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

      DispatchQueue.main.async {
        if canRegister {
          UIApplication.shared.registerForRemoteNotifications()
        }

        result?(canRegister)
      }
    }
  }

  private func handleNotificationPermissionRequest(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      DispatchQueue.main.async {
        if granted {
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
    return captureNotificationUserInfo(
      response.notification.request.content.userInfo,
      actionIdentifier: response.actionIdentifier,
      source: "apns-response"
    )
  }

  @discardableResult
  private func captureNotificationUserInfo(
    _ userInfo: [AnyHashable: Any],
    actionIdentifier: String?,
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

    pendingNotificationResponse = payload
    DispatchQueue.main.async { [weak self] in
      self?.deliverPendingNotificationResponse()
    }
    return true
  }

  private func deliverPendingNotificationResponse() {
    guard let payload = pendingNotificationResponse else {
      return
    }
    guard let notificationsChannel else {
      NSLog(
        "intergalactic_ios_notification_response_delivery_deferred reason=channel_not_ready response_id_present=%@",
        payload["response_id"] == nil ? "false" : "true"
      )
      return
    }

    NSLog(
      "intergalactic_ios_notification_response_delivered response_id_present=%@",
      payload["response_id"] == nil ? "false" : "true"
    )
    notificationsChannel.invokeMethod("notificationResponseReceived", arguments: payload)
  }

  private func handleNotificationResponseAcknowledgement(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let responseId = arguments["response_id"] as? String
    else {
      result(false)
      return
    }

    if pendingNotificationResponse?["response_id"] as? String == responseId {
      pendingNotificationResponse = nil
      NSLog("intergalactic_ios_notification_response_acknowledged")
      result(true)
      return
    }

    result(false)
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
