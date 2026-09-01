import AVFoundation
import AVKit
import Flutter
import UIKit
import WebRTC

private extension Notification.Name {
  static let interGalacticPreparedPiPTrack = Notification.Name(
    "InterGalacticPreparedPiPTrack"
  )
}

@available(iOS 15.0, *)
final class CallPiPCoordinator: NSObject {
  typealias PresentationChanged = ([String: Any]) -> Void
  typealias ActionRequested = (String) -> Void

  init(
    presentationChanged: @escaping PresentationChanged,
    actionRequested: @escaping ActionRequested
  ) {
    self.presentationChanged = presentationChanged
    self.actionRequested = actionRequested
    super.init()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handlePreparedTrackNotification(_:)),
      name: .interGalacticPreparedPiPTrack,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    clearContentState()
  }

  private let presentationChanged: PresentationChanged
  private let actionRequested: ActionRequested
  private var controller: AVPictureInPictureController?
  private var activeVideoCallSourceHostView: UIView?
  private var videoCallContentViewController: AVPictureInPictureVideoCallViewController?
  private var metalVideoView: RTCMTLVideoView?
  private var sampleBufferLayer: AVSampleBufferDisplayLayer?
  private var sampleBufferRenderer: SampleBufferVideoRenderer?
  private var activeContentSource = "none"
  private var sessionId: String?
  private var selectedTrackHash: String?
  private var selectedParticipantHash: String?
  private var selectedStreamHash: String?
  private var preparedTargets: [String: PreparedPiPTrack] = [:]
  private var activeVideoTrack: RTCVideoTrack?
  private var didLogFirstFrame = false
  private var possibleObservation: NSKeyValueObservation?
  private var startTimeoutWorkItem: DispatchWorkItem?
  private var firstFrameTimeoutWorkItem: DispatchWorkItem?
  private var pendingStartResult: FlutterResult?

  var presentationState: [String: Any] {
    [
      "pictureInPicture": controller?.isPictureInPictureActive == true,
      "resizedPopout": false,
      "sessionId": sessionId ?? "",
    ]
  }

  func enter(
    call: FlutterMethodCall,
    result: @escaping FlutterResult,
    callBackgroundActive: Bool,
    sourceView rootView: UIView?
  ) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let requestedSessionId = (arguments["sessionId"] as? String)?.nilIfEmpty

    guard callBackgroundActive else {
      NSLog("intergalactic_ios_call_pip event=start_rejected reason=no_active_call")
      discardPreparedTarget(for: requestedSessionId)
      result(false)
      return
    }

    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      NSLog("intergalactic_ios_call_pip event=start_rejected reason=device_unsupported")
      discardPreparedTarget(for: requestedSessionId)
      result(false)
      return
    }

    guard let rootView else {
      NSLog("intergalactic_ios_call_pip event=start_rejected reason=no_root_view")
      discardPreparedTarget(for: requestedSessionId)
      result(false)
      return
    }

    if controller?.isPictureInPictureActive == true {
      NSLog("intergalactic_ios_call_pip event=start_reused active=true")
      discardPreparedTarget(for: requestedSessionId)
      result(true)
      return
    }

    if pendingStartResult != nil {
      NSLog("intergalactic_ios_call_pip event=start_rejected reason=start_already_pending")
      discardPreparedTarget(for: requestedSessionId)
      result(false)
      return
    }

    guard let preparedTrack = preparedTarget(for: requestedSessionId) else {
      NSLog("intergalactic_ios_call_pip event=start_rejected reason=no_prepared_track")
      discardPreparedTarget(for: requestedSessionId)
      result(false)
      return
    }

    let initialContentSize = preferredSize(call: call)
    let displayLayer = AVSampleBufferDisplayLayer()
    displayLayer.videoGravity = .resizeAspect
    displayLayer.backgroundColor = UIColor.black.cgColor
    displayLayer.frame = CGRect(origin: .zero, size: initialContentSize)
    displayLayer.contentsScale = rootView.window?.screen.scale ?? UIScreen.main.scale
    configureSampleBufferTimebase(displayLayer)
    let videoCallContentViewController = LiveKitPiPVideoCallViewController(
      displayLayer: displayLayer
    )
    videoCallContentViewController.preferredContentSize = initialContentSize

    let sourceHostView = attachActiveVideoCallSourceHost(
      call: call,
      sourceView: rootView
    )
    let contentSource = AVPictureInPictureController.ContentSource(
      activeVideoCallSourceView: sourceHostView,
      contentViewController: videoCallContentViewController
    )
    let nextController = AVPictureInPictureController(contentSource: contentSource)
    nextController.delegate = self
    nextController.canStartPictureInPictureAutomaticallyFromInline = true
    nextController.requiresLinearPlayback = true

    sessionId = requestedSessionId
    selectedTrackHash = preparedTrack.trackHash
    selectedParticipantHash = preparedTrack.participantHash
    selectedStreamHash = preparedTrack.streamHash
    activeContentSource = "sample_buffer_call"
    self.videoCallContentViewController = videoCallContentViewController
    sampleBufferLayer = displayLayer
    controller = nextController
    pendingStartResult = result
    configureSampleBufferRenderer(displayLayer, preparedTrack: preparedTrack)

    NSLog(
      "intergalactic_ios_call_pip event=start_waiting_for_frame content_source=sample_buffer_call selected_track_hash=%@ participant_hash=%@",
      selectedTrackHash ?? "",
      selectedParticipantHash ?? ""
    )
    scheduleFirstFrameTimeout(nextController)
  }

  func stop(reason: String = "requested") {
    guard let controller else {
      return
    }

    if controller.isPictureInPictureActive {
      NSLog("intergalactic_ios_call_pip event=stop_requested reason=%@", reason)
      controller.stopPictureInPicture()
    } else {
      resolvePendingStart(false)
      clearContentState()
      presentationChanged(presentationState)
    }
  }

  private func preferredSize(call: FlutterMethodCall) -> CGSize {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let numerator = max(1, arguments["aspectRatioNumerator"] as? Int ?? 16)
    let denominator = max(1, arguments["aspectRatioDenominator"] as? Int ?? 9)
    let width: CGFloat = 320
    let height = max(180, width * CGFloat(denominator) / CGFloat(numerator))
    return CGSize(width: width, height: height)
  }

  private func sourceRect(call: FlutterMethodCall, sourceView: UIView) -> CGRect? {
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

  private func attachActiveVideoCallSourceHost(
    call: FlutterMethodCall,
    sourceView: UIView
  ) -> UIView {
    activeVideoCallSourceHostView?.removeFromSuperview()

    let fallbackSize = preferredSize(call: call)
    let sourceBounds = sourceRect(call: call, sourceView: sourceView) ?? sourceView.bounds
    let hostFrame = aspectFitRect(size: fallbackSize, inside: sourceBounds)
    var resolvedFrame = hostFrame.intersection(sourceView.bounds)
    if resolvedFrame.isNull || resolvedFrame.isEmpty {
      resolvedFrame = aspectFitRect(size: fallbackSize, inside: sourceView.bounds)
    }
    if resolvedFrame.isNull || resolvedFrame.isEmpty {
      resolvedFrame = CGRect(
        x: 0,
        y: 0,
        width: min(320, max(1, sourceView.bounds.width)),
        height: min(180, max(1, sourceView.bounds.height))
      )
    }
    let hostView = UIView(frame: resolvedFrame)
    hostView.backgroundColor = .clear
    hostView.clipsToBounds = true
    hostView.isUserInteractionEnabled = false
    hostView.accessibilityElementsHidden = true
    hostView.autoresizingMask = []

    sourceView.addSubview(hostView)
    sourceView.layoutIfNeeded()

    activeVideoCallSourceHostView = hostView
    NSLog(
      "intergalactic_ios_call_pip event=source_view_attached window=%@ frame=%dx%d",
      (sourceView.window == nil ? "false" : "true"),
      Int(hostView.bounds.width),
      Int(hostView.bounds.height)
    )
    return hostView
  }

  private func aspectFitRect(size: CGSize, inside bounds: CGRect) -> CGRect {
    guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else {
      return bounds
    }

    let scale = min(bounds.width / size.width, bounds.height / size.height)
    let fittedSize = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(
      x: bounds.midX - fittedSize.width / 2,
      y: bounds.midY - fittedSize.height / 2,
      width: fittedSize.width,
      height: fittedSize.height
    )
  }

  private func preferredSize(forVideoSize videoSize: CGSize) -> CGSize {
    guard videoSize.width > 0, videoSize.height > 0 else {
      return CGSize(width: 320, height: 180)
    }

    if videoSize.width >= videoSize.height {
      let width: CGFloat = 320
      let height = max(120, width * videoSize.height / videoSize.width)
      return CGSize(width: width, height: height)
    }

    let height: CGFloat = 320
    let width = max(120, height * videoSize.width / videoSize.height)
    return CGSize(width: width, height: height)
  }

  private func configureSampleBufferTimebase(_ displayLayer: AVSampleBufferDisplayLayer) {
    var timebase: CMTimebase?
    let status = CMTimebaseCreateWithSourceClock(
      allocator: kCFAllocatorDefault,
      sourceClock: CMClockGetHostTimeClock(),
      timebaseOut: &timebase
    )
    guard status == noErr, let timebase else {
      NSLog("intergalactic_ios_call_pip event=timebase_failed status=%d", status)
      return
    }

    CMTimebaseSetTime(timebase, time: .zero)
    CMTimebaseSetRate(timebase, rate: 1.0)
    displayLayer.controlTimebase = timebase
  }

  private func configureSampleBufferRenderer(
    _ displayLayer: AVSampleBufferDisplayLayer,
    preparedTrack: PreparedPiPTrack
  ) {
    let renderer = SampleBufferVideoRenderer(
      displayLayer: displayLayer,
      trackHash: preparedTrack.trackHash
    )
    renderer.delegate = self
    sampleBufferRenderer = renderer
    activeVideoTrack = preparedTrack.track
    preparedTrack.track.add(renderer)
    NSLog(
      "intergalactic_ios_call_pip event=renderer_attached content_source=sample_buffer selected_track_hash=%@",
      preparedTrack.trackHash
    )
  }

  private func scheduleFirstFrameTimeout(_ controller: AVPictureInPictureController) {
    firstFrameTimeoutWorkItem?.cancel()
    let timeout = DispatchWorkItem { [weak self, weak controller] in
      guard
        let self,
        let controller,
        self.controller === controller,
        self.pendingStartResult != nil,
        !self.didLogFirstFrame
      else {
        return
      }

      NSLog(
        "intergalactic_ios_call_pip event=start_failed reason=first_frame_timeout selected_track_hash=%@",
        self.selectedTrackHash ?? ""
      )
      self.resolvePendingStart(false)
      self.clearContentState()
      self.presentationChanged(self.presentationState)
    }
    firstFrameTimeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timeout)
  }

  private func scheduleStart(_ controller: AVPictureInPictureController) {
    possibleObservation?.invalidate()
    startTimeoutWorkItem?.cancel()

    let startIfPossible: () -> Void = { [weak self, weak controller] in
      guard
        let self,
        let controller,
        self.controller === controller,
        self.pendingStartResult != nil
      else {
        return
      }

      guard controller.isPictureInPicturePossible else {
        return
      }

      self.possibleObservation?.invalidate()
      self.possibleObservation = nil
      self.startTimeoutWorkItem?.cancel()
      self.startTimeoutWorkItem = nil
      NSLog("intergalactic_ios_call_pip event=start_requested possible=true")
      controller.startPictureInPicture()
    }

    possibleObservation = controller.observe(
      \.isPictureInPicturePossible,
      options: [.initial, .new]
    ) { _, _ in
      DispatchQueue.main.async {
        startIfPossible()
      }
    }

    let timeout = DispatchWorkItem { [weak self, weak controller] in
      guard
        let self,
        let controller,
        self.controller === controller,
        self.pendingStartResult != nil
      else {
        return
      }

      if controller.isPictureInPicturePossible {
        startIfPossible()
        return
      }

      NSLog("intergalactic_ios_call_pip event=start_failed reason=not_possible_timeout")
      self.resolvePendingStart(false)
      self.clearContentState()
      self.presentationChanged(self.presentationState)
    }
    startTimeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: timeout)
  }

  private func preparedTarget(for sessionId: String?) -> PreparedPiPTrack? {
    if let sessionId, let target = preparedTargets[sessionId] {
      return target
    }
    return preparedTargets[PreparedPiPTrack.defaultSessionKey]
  }

  private func discardPreparedTarget(for sessionId: String?) {
    if let sessionId {
      preparedTargets.removeValue(forKey: sessionId)
    }
    preparedTargets.removeValue(forKey: PreparedPiPTrack.defaultSessionKey)
  }

  @objc private func handlePreparedTrackNotification(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let track = userInfo["track"] as? RTCVideoTrack
    else {
      NSLog("intergalactic_ios_call_pip event=track_prepare_failed reason=missing_track")
      return
    }

    let preparedTrack = PreparedPiPTrack(
      sessionId: (userInfo["sessionId"] as? String)?.nilIfEmpty,
      track: track,
      trackHash: (userInfo["trackHash"] as? String)?.nilIfEmpty ?? "unknown",
      streamHash: (userInfo["streamHash"] as? String)?.nilIfEmpty,
      participantHash: (userInfo["participantHash"] as? String)?.nilIfEmpty
    )
    preparedTargets[preparedTrack.storageKey] = preparedTrack
    NSLog(
      "intergalactic_ios_call_pip event=track_prepared selected_track_hash=%@ participant_hash=%@",
      preparedTrack.trackHash,
      preparedTrack.participantHash ?? ""
    )
  }

  private func clearContentState() {
    startTimeoutWorkItem?.cancel()
    startTimeoutWorkItem = nil
    firstFrameTimeoutWorkItem?.cancel()
    firstFrameTimeoutWorkItem = nil
    possibleObservation?.invalidate()
    possibleObservation = nil
    pendingStartResult = nil

    if let activeVideoTrack, let metalVideoView {
      activeVideoTrack.remove(metalVideoView)
    }
    if let activeVideoTrack, let sampleBufferRenderer {
      activeVideoTrack.remove(sampleBufferRenderer)
    }
    activeVideoTrack = nil
    didLogFirstFrame = false
    metalVideoView?.delegate = nil
    metalVideoView?.removeFromSuperview()
    metalVideoView = nil
    sampleBufferRenderer = nil
    sampleBufferLayer?.stopRequestingMediaData()
    sampleBufferLayer?.flushAndRemoveImage()
    sampleBufferLayer?.removeFromSuperlayer()
    sampleBufferLayer = nil
    activeVideoCallSourceHostView?.removeFromSuperview()
    activeVideoCallSourceHostView = nil
    videoCallContentViewController = nil

    controller?.delegate = nil
    controller = nil
    if let sessionId {
      preparedTargets.removeValue(forKey: sessionId)
    }
    preparedTargets.removeValue(forKey: PreparedPiPTrack.defaultSessionKey)
    sessionId = nil
    selectedTrackHash = nil
    selectedParticipantHash = nil
    selectedStreamHash = nil
    activeContentSource = "none"
  }

  private func resolvePendingStart(_ value: Bool) {
    guard let pendingStartResult else {
      return
    }
    self.pendingStartResult = nil
    pendingStartResult(value)
  }
}

@available(iOS 15.0, *)
extension CallPiPCoordinator: AVPictureInPictureControllerDelegate,
  RTCVideoViewDelegate,
  SampleBufferVideoRendererDelegate {
  func videoView(
    _ videoView: RTCVideoRenderer,
    didChangeVideoSize size: CGSize
  ) {
    handleFirstVideoFrame(size: size, contentSource: "rtc_metal")
  }

  fileprivate func sampleBufferVideoRenderer(
    _ renderer: SampleBufferVideoRenderer,
    didRenderFirstFrame size: CGSize
  ) {
    handleFirstVideoFrame(size: size, contentSource: "sample_buffer")
  }

  private func handleFirstVideoFrame(size: CGSize, contentSource: String) {
    guard !didLogFirstFrame else {
      return
    }
    didLogFirstFrame = true
    firstFrameTimeoutWorkItem?.cancel()
    firstFrameTimeoutWorkItem = nil
    NSLog(
      "intergalactic_ios_call_pip event=first_frame_rendered content_source=%@ selected_track_hash=%@ size=%dx%d",
      contentSource,
      selectedTrackHash ?? "",
      Int(size.width),
      Int(size.height)
    )
    let contentSize = preferredSize(forVideoSize: size)
    videoCallContentViewController?.preferredContentSize = contentSize
    videoCallContentViewController?.view.frame = CGRect(origin: .zero, size: contentSize)
    videoCallContentViewController?.view.setNeedsLayout()
    NSLog(
      "intergalactic_ios_call_pip event=content_size_updated width=%d height=%d",
      Int(contentSize.width),
      Int(contentSize.height)
    )
    if let controller {
      scheduleStart(controller)
    }
  }

  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    NSLog("intergalactic_ios_call_pip event=will_start")
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    NSLog(
      "intergalactic_ios_call_pip event=did_start content_source=%@ selected_track_hash=%@ participant_hash=%@",
      activeContentSource,
      selectedTrackHash ?? "",
      selectedParticipantHash ?? ""
    )
    resolvePendingStart(true)
    presentationChanged(presentationState)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    NSLog(
      "intergalactic_ios_call_pip event=start_failed error=%@",
      error.localizedDescription
    )
    resolvePendingStart(false)
    clearContentState()
    presentationChanged(presentationState)
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
    resolvePendingStart(false)
    clearContentState()
    presentationChanged(presentationState)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    NSLog("intergalactic_ios_call_pip event=restore_user_interface")
    actionRequested("returnToCall")
    completionHandler(true)
  }
}

@available(iOS 15.0, *)
private final class LiveKitPiPVideoCallViewController: AVPictureInPictureVideoCallViewController {
  init(displayLayer: AVSampleBufferDisplayLayer) {
    self.displayLayer = displayLayer
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  private let displayLayer: AVSampleBufferDisplayLayer

  override func loadView() {
    view = SampleBufferPiPContentView(displayLayer: displayLayer)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    NSLog(
      "intergalactic_ios_call_pip event=content_view_did_appear window=%@ bounds=%dx%d",
      (view.window == nil ? "false" : "true"),
      Int(view.bounds.width),
      Int(view.bounds.height)
    )
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
  }
}

@available(iOS 15.0, *)
private final class SampleBufferPiPContentView: UIView {
  private let displayLayer: AVSampleBufferDisplayLayer

  init(displayLayer: AVSampleBufferDisplayLayer) {
    self.displayLayer = displayLayer
    super.init(frame: .zero)

    backgroundColor = .black
    clipsToBounds = true
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
    layer.addSublayer(displayLayer)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    displayLayer.frame = bounds
  }
}

@available(iOS 15.0, *)
private struct PreparedPiPTrack {
  static let defaultSessionKey = "__default__"

  let sessionId: String?
  let track: RTCVideoTrack
  let trackHash: String
  let streamHash: String?
  let participantHash: String?

  var storageKey: String {
    sessionId ?? Self.defaultSessionKey
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

@available(iOS 15.0, *)
fileprivate protocol SampleBufferVideoRendererDelegate: AnyObject {
  func sampleBufferVideoRenderer(
    _ renderer: SampleBufferVideoRenderer,
    didRenderFirstFrame size: CGSize
  )
}

@available(iOS 15.0, *)
fileprivate final class SampleBufferVideoRenderer: NSObject, RTCVideoRenderer {
  init(displayLayer: AVSampleBufferDisplayLayer, trackHash: String) {
    self.displayLayer = displayLayer
    self.trackHash = trackHash
    super.init()
  }

  weak var delegate: SampleBufferVideoRendererDelegate?

  private let displayLayer: AVSampleBufferDisplayLayer
  private let trackHash: String
  private let renderQueue = DispatchQueue(
    label: "chat.intergalactic.call-pip.sample-buffer-renderer"
  )
  private var formatDescription: CMVideoFormatDescription?
  private var lastPresentationTime = CMTime.invalid
  private var renderedFrameCount = 0
  private var unsupportedFrameCount = 0
  private var droppedFrameCount = 0
  private var currentSize = CGSize.zero

  func setSize(_ size: CGSize) {
    renderQueue.async { [weak self] in
      self?.currentSize = size
    }
  }

  func renderFrame(_ frame: RTCVideoFrame?) {
    guard let frame else {
      return
    }

    renderQueue.async { [weak self] in
      self?.enqueue(frame)
    }
  }

  private func enqueue(_ frame: RTCVideoFrame) {
    guard let pixelBuffer = pixelBuffer(from: frame) else {
      unsupportedFrameCount += 1
      if unsupportedFrameCount == 1 || unsupportedFrameCount % 60 == 0 {
        NSLog(
          "intergalactic_ios_call_pip event=frame_dropped reason=unsupported_buffer selected_track_hash=%@ count=%d",
          trackHash,
          unsupportedFrameCount
        )
      }
      return
    }

    var nextFormatDescription: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &nextFormatDescription
    )
    guard formatStatus == noErr, let nextFormatDescription else {
      NSLog(
        "intergalactic_ios_call_pip event=frame_dropped reason=format_description_failed selected_track_hash=%@ status=%d",
        trackHash,
        formatStatus
      )
      return
    }
    formatDescription = nextFormatDescription

    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 30),
      presentationTimeStamp: nextPresentationTime(for: frame),
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: nextFormatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr, let sampleBuffer else {
      NSLog(
        "intergalactic_ios_call_pip event=frame_dropped reason=sample_buffer_failed selected_track_hash=%@ status=%d",
        trackHash,
        sampleStatus
      )
      return
    }

    markDisplayImmediately(sampleBuffer)

    DispatchQueue.main.async { [weak self] in
      self?.enqueueOnDisplayLayer(sampleBuffer, width: frame.width, height: frame.height)
    }
  }

  private func enqueueOnDisplayLayer(
    _ sampleBuffer: CMSampleBuffer,
    width: Int32,
    height: Int32
  ) {
    if displayLayer.status == .failed {
      NSLog(
        "intergalactic_ios_call_pip event=display_layer_failed selected_track_hash=%@ error=%@",
        trackHash,
        displayLayer.error?.localizedDescription ?? "unknown"
      )
      displayLayer.flushAndRemoveImage()
    }

    guard displayLayer.isReadyForMoreMediaData else {
      droppedFrameCount += 1
      if droppedFrameCount == 1 || droppedFrameCount % 60 == 0 {
        NSLog(
          "intergalactic_ios_call_pip event=frame_dropped reason=display_layer_backpressure selected_track_hash=%@ count=%d",
          trackHash,
          droppedFrameCount
        )
      }
      return
    }

    displayLayer.enqueue(sampleBuffer)
    renderedFrameCount += 1
    if renderedFrameCount == 1 {
      delegate?.sampleBufferVideoRenderer(
        self,
        didRenderFirstFrame: CGSize(width: CGFloat(width), height: CGFloat(height))
      )
    } else if renderedFrameCount % 120 == 0 {
      NSLog(
        "intergalactic_ios_call_pip event=frames_enqueued selected_track_hash=%@ count=%d",
        trackHash,
        renderedFrameCount
      )
    }
  }

  private func pixelBuffer(from frame: RTCVideoFrame) -> CVPixelBuffer? {
    if let cvPixelBuffer = frame.buffer as? RTCCVPixelBuffer {
      return cvPixelBuffer.pixelBuffer
    }

    return makePixelBuffer(from: frame.buffer.toI420())
  }

  private func makePixelBuffer(from i420: RTCI420BufferProtocol) -> CVPixelBuffer? {
    let width = Int(i420.width)
    let height = Int(i420.height)
    guard width > 0, height > 0 else {
      return nil
    }

    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferMetalCompatibilityKey: true,
    ]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      attributes as CFDictionary,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else {
      return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard
      let yDestination = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
      let uvDestination = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
    else {
      return nil
    }

    copyPlane(
      source: i420.dataY,
      sourceStride: Int(i420.strideY),
      destination: yDestination.assumingMemoryBound(to: UInt8.self),
      destinationStride: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0),
      width: width,
      height: height
    )
    interleaveChroma(
      sourceU: i420.dataU,
      sourceV: i420.dataV,
      sourceStrideU: Int(i420.strideU),
      sourceStrideV: Int(i420.strideV),
      destination: uvDestination.assumingMemoryBound(to: UInt8.self),
      destinationStride: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1),
      width: max(1, width / 2),
      height: max(1, height / 2)
    )
    return pixelBuffer
  }

  private func copyPlane(
    source: UnsafePointer<UInt8>,
    sourceStride: Int,
    destination: UnsafeMutablePointer<UInt8>,
    destinationStride: Int,
    width: Int,
    height: Int
  ) {
    for row in 0..<height {
      destination.advanced(by: row * destinationStride).update(
        from: source.advanced(by: row * sourceStride),
        count: width
      )
    }
  }

  private func interleaveChroma(
    sourceU: UnsafePointer<UInt8>,
    sourceV: UnsafePointer<UInt8>,
    sourceStrideU: Int,
    sourceStrideV: Int,
    destination: UnsafeMutablePointer<UInt8>,
    destinationStride: Int,
    width: Int,
    height: Int
  ) {
    for row in 0..<height {
      let uRow = sourceU.advanced(by: row * sourceStrideU)
      let vRow = sourceV.advanced(by: row * sourceStrideV)
      let destinationRow = destination.advanced(by: row * destinationStride)
      for column in 0..<width {
        destinationRow[column * 2] = uRow[column]
        destinationRow[column * 2 + 1] = vRow[column]
      }
    }
  }

  private func nextPresentationTime(for frame: RTCVideoFrame) -> CMTime {
    let frameTime = frame.timeStampNs > 0
      ? CMTime(value: frame.timeStampNs, timescale: 1_000_000_000)
      : CMClockGetTime(CMClockGetHostTimeClock())
    let minimumStep = CMTime(value: 1, timescale: 600)

    if lastPresentationTime.isValid,
      CMTimeCompare(frameTime, CMTimeAdd(lastPresentationTime, minimumStep)) <= 0 {
      lastPresentationTime = CMTimeAdd(lastPresentationTime, minimumStep)
    } else {
      lastPresentationTime = frameTime
    }
    return lastPresentationTime
  }

  private func markDisplayImmediately(_ sampleBuffer: CMSampleBuffer) {
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: true
      ),
      CFArrayGetCount(attachments) > 0
    else {
      return
    }

    let attachment = unsafeBitCast(
      CFArrayGetValueAtIndex(attachments, 0),
      to: CFMutableDictionary.self
    )
    CFDictionarySetValue(
      attachment,
      Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
      Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
    )
  }
}
