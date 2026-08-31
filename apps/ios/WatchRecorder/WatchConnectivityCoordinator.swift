import Foundation
@preconcurrency import WatchConnectivity
import os

@MainActor
protocol WatchConnectivityCoordinatorDelegate: AnyObject {
    func watchConnectivityDidActivate(_ state: WCSessionActivationState, error: Error?)
    func watchConnectivityDidReceive(_ acknowledgement: WatchDurableAck)
    func watchConnectivityDidFinishFileTransfer(fileName: String, error: Error?)
}

@MainActor
final class WatchConnectivityCoordinator: NSObject, @preconcurrency WCSessionDelegate {
    static let shared = WatchConnectivityCoordinator()

    weak var delegate: WatchConnectivityCoordinatorDelegate?

    private let logger = Logger(subsystem: "com.shepswork.noted.watchkitapp", category: "WatchConnectivity")

    private override init() {
        super.init()
    }

    var isSupported: Bool { WCSession.isSupported() }

    var outstandingFileNames: Set<String> {
        guard isSupported else { return [] }
        return Set(WCSession.default.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
    }

    func activate() {
        guard isSupported else {
            logger.info("WatchConnectivity is not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func queueFile(fileURL: URL, metadata: [String: Any]) throws {
        guard isSupported else { throw WatchSpikeError.connectivityUnavailable }
        WCSession.default.transferFile(fileURL, metadata: metadata)
    }

    func queueUserInfo(_ userInfo: [String: Any]) throws {
        guard isSupported else { throw WatchSpikeError.connectivityUnavailable }
        WCSession.default.transferUserInfo(userInfo)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        delegate?.watchConnectivityDidActivate(activationState, error: error)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        do {
            let acknowledgement = try WatchCaptureProtocol.ack(from: userInfo)
            delegate?.watchConnectivityDidReceive(acknowledgement)
        } catch {
            logger.error("Invalid durable acknowledgement: \(error.localizedDescription, privacy: .public)")
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        delegate?.watchConnectivityDidFinishFileTransfer(
            fileName: fileTransfer.file.fileURL.lastPathComponent,
            error: error
        )
    }
}
