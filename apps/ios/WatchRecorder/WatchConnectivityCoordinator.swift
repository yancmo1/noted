import Foundation
@preconcurrency import WatchConnectivity
import os

@MainActor
protocol WatchConnectivityCoordinatorDelegate: AnyObject {
    func watchConnectivityDidActivate(_ state: WCSessionActivationState, error: Error?)
    func watchConnectivityDidReceive(_ acknowledgement: WatchDurableAck)
    func watchConnectivityDidFinishFileTransfer(fileName: String, error: Error?)
    func watchConnectivityDidReceiveStartRequest(_ request: WatchStartCaptureRequest) async -> WatchStartCaptureAck
    func watchConnectivityDidReceiveStopRequest(_ request: WatchStopCaptureRequest) async -> WatchStopCaptureAck
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

    func sendStopAcknowledgement(_ acknowledgement: WatchStopCaptureAck) {
        guard isSupported else { return }
        do {
            let message = try WatchCaptureProtocol.stopAckMessage(for: acknowledgement)
            let session = WCSession.default
            if session.activationState == .activated, session.isReachable {
                session.sendMessage(message, replyHandler: nil) { [logger] error in
                    logger.error("Could not send Watch stop acknowledgement: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                session.transferUserInfo(message)
            }
        } catch {
            logger.error("Could not encode Watch stop acknowledgement: \(error.localizedDescription, privacy: .public)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            self?.delegate?.watchConnectivityDidActivate(activationState, error: error)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        do {
            let acknowledgement = try WatchCaptureProtocol.ack(from: userInfo)
            Task { @MainActor [weak self] in
                self?.delegate?.watchConnectivityDidReceive(acknowledgement)
            }
        } catch {
            logger.error("Invalid durable acknowledgement: \(error.localizedDescription, privacy: .public)")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else {
                replyHandler(WatchCaptureProtocol.commandErrorMessage(for: WatchSpikeError.connectivityUnavailable))
                return
            }

            do {
                switch message["kind"] as? String {
                case WatchCaptureProtocol.startRequestKind:
                    let request = try WatchCaptureProtocol.startRequest(from: message)
                    guard let delegate else { throw WatchSpikeError.connectivityUnavailable }
                    let acknowledgement = await delegate.watchConnectivityDidReceiveStartRequest(request)
                    replyHandler(try WatchCaptureProtocol.startAckMessage(for: acknowledgement))
                case WatchCaptureProtocol.stopRequestKind:
                    let request = try WatchCaptureProtocol.stopRequest(from: message)
                    guard let delegate else { throw WatchSpikeError.connectivityUnavailable }
                    let acknowledgement = await delegate.watchConnectivityDidReceiveStopRequest(request)
                    replyHandler(try WatchCaptureProtocol.stopAckMessage(for: acknowledgement))
                default:
                    throw WatchSpikeError.connectivityUnavailable
                }
            } catch {
                replyHandler(WatchCaptureProtocol.commandErrorMessage(for: error))
            }
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let fileName = fileTransfer.file.fileURL.lastPathComponent
        Task { @MainActor [weak self] in
            self?.delegate?.watchConnectivityDidFinishFileTransfer(
                fileName: fileName,
                error: error
            )
        }
    }
}
