//
//  SampleHandler.swift
//  Inter Galactic Broadcast Extension
//

import OSLog
import ReplayKit

let broadcastLogger = OSLog(
    subsystem: "chat.intergalactic.app",
    category: "Broadcast"
)

private enum Constants {
    static let appGroupIdentifier = "group.chat.intergalactic.app"
}

class SampleHandler: RPBroadcastSampleHandler {
    private var clientConnection: SocketConnection?
    private var uploader: SampleUploader?

    private var frameCount: Int = 0

    var socketFilePath: String {
        let sharedContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier
        )
        return sharedContainer?.appendingPathComponent("rtc_SSFD").path ?? ""
    }

    override init() {
        super.init()

        if let connection = SocketConnection(filePath: socketFilePath) {
            clientConnection = connection
            setupConnection()
            uploader = SampleUploader(connection: connection)
        }

        os_log(.debug, log: broadcastLogger, "%{public}s", socketFilePath)
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        frameCount = 0
        DarwinNotificationCenter.shared.postNotification(.broadcastStarted)
        openConnection()
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        DarwinNotificationCenter.shared.postNotification(.broadcastStopped)
        clientConnection?.close()
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        switch sampleBufferType {
        case .video:
            uploader?.send(sample: sampleBuffer)
        default:
            break
        }
    }
}

private extension SampleHandler {
    func setupConnection() {
        clientConnection?.didClose = { [weak self] error in
            os_log(
                .debug,
                log: broadcastLogger,
                "client connection did close \(String(describing: error))"
            )

            if let error {
                self?.finishBroadcastWithError(error)
            } else {
                let screenSharingStoppedCode = 10001
                let customError = NSError(
                    domain: RPRecordingErrorDomain,
                    code: screenSharingStoppedCode,
                    userInfo: [NSLocalizedDescriptionKey: "Screen sharing stopped"]
                )
                self?.finishBroadcastWithError(customError)
            }
        }
    }

    func openConnection() {
        let queue = DispatchQueue(label: "broadcast.connectTimer")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(100),
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            guard self?.clientConnection?.open() == true else {
                return
            }

            timer.cancel()
        }

        timer.resume()
    }
}
