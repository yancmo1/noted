import Foundation
@preconcurrency import WatchConnectivity
import os

struct WatchTransferIngestResult: Equatable {
    let destinationURL: URL
    let manifestURL: URL
    let wasExisting: Bool
}

extension Notification.Name {
    static let notedWatchTransferReceived = Notification.Name("noted.watchTransferReceived")
}

final class WatchTransferStore {
    let durableDirectory: URL

    private let fileManager = FileManager.default
    private let lock = NSLock()

    init(durableDirectory: URL) {
        self.durableDirectory = durableDirectory
        try? fileManager.createDirectory(at: durableDirectory, withIntermediateDirectories: true)
    }

    func ingest(fileURL: URL, manifest: WatchTransferManifest) throws -> WatchTransferIngestResult {
        lock.lock()
        defer { lock.unlock() }

        let destination = durableDirectory.appendingPathComponent(safeFileName(for: manifest))
        let existingManifestURL = manifestURL(for: manifest)
        let wasExisting = fileManager.fileExists(atPath: destination.path)

        if fileManager.fileExists(atPath: existingManifestURL.path) {
            let stored = try JSONDecoder().decode(WatchTransferManifest.self, from: Data(contentsOf: existingManifestURL))
            try WatchCaptureProtocol.validate(manifest: stored)
            guard stored == manifest else { throw WatchCaptureProtocolError.manifestMismatch }
        }

        if wasExisting {
            do {
                try validate(fileURL: destination, manifest: manifest)
            } catch WatchCaptureProtocolError.checksumMismatch {
                try replaceCorruptDestination(destination, with: fileURL, manifest: manifest)
            }
        } else {
            try copyValidatedFile(fileURL, to: destination, manifest: manifest)
        }

        if !fileManager.fileExists(atPath: existingManifestURL.path) {
            try JSONEncoder().encode(manifest).write(to: existingManifestURL, options: .atomic)
        }

        return WatchTransferIngestResult(
            destinationURL: destination,
            manifestURL: existingManifestURL,
            wasExisting: wasExisting
        )
    }

    func durableAcknowledgement(for request: WatchAcknowledgementStatusRequest) throws -> WatchDurableAck? {
        lock.lock()
        defer { lock.unlock() }

        let url = manifestURL(sourceID: request.sourceID, sequence: request.sequence)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let stored = try JSONDecoder().decode(WatchTransferManifest.self, from: Data(contentsOf: url))
        try WatchCaptureProtocol.validate(manifest: stored)
        guard stored.sourceID == request.sourceID,
              stored.sequence == request.sequence,
              stored.sha256 == request.sha256 else { return nil }
        let destination = durableDirectory.appendingPathComponent(safeFileName(for: stored))
        try validate(fileURL: destination, manifest: stored)
        return WatchDurableAck(
            protocolVersion: stored.protocolVersion,
            sourceID: stored.sourceID,
            sequence: stored.sequence,
            sha256: stored.sha256,
            acknowledgedAt: Date()
        )
    }

    func pendingTransfers() -> [(manifest: WatchTransferManifest, fileURL: URL)] {
        lock.lock()
        defer { lock.unlock() }

        let manifests = (try? fileManager.contentsOfDirectory(
            at: durableDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension.lowercased() == "json" } ?? []

        return manifests.compactMap { manifestURL in
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(WatchTransferManifest.self, from: data),
                  (try? WatchCaptureProtocol.validate(manifest: manifest)) != nil else {
                return nil
            }
            let fileURL = durableDirectory.appendingPathComponent(safeFileName(for: manifest))
            guard fileManager.fileExists(atPath: fileURL.path),
                  (try? validate(fileURL: fileURL, manifest: manifest)) != nil else {
                return nil
            }
            return (manifest: manifest, fileURL: fileURL)
        }
    }

    private func validate(fileURL: URL, manifest: WatchTransferManifest) throws {
        try WatchCaptureProtocol.validate(manifest: manifest)
        guard try WatchCaptureProtocol.byteSize(of: fileURL) == manifest.byteSize,
              try WatchCaptureProtocol.checksum(of: fileURL) == manifest.sha256 else {
            throw WatchCaptureProtocolError.checksumMismatch
        }
    }

    private func copyValidatedFile(_ source: URL, to destination: URL, manifest: WatchTransferManifest) throws {
        let temporary = durableDirectory.appendingPathComponent(".\(manifest.sourceID.uuidString)-\(manifest.sequence).tmp")
        try? fileManager.removeItem(at: temporary)
        try fileManager.copyItem(at: source, to: temporary)
        do {
            try validate(fileURL: temporary, manifest: manifest)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func replaceCorruptDestination(_ destination: URL, with source: URL, manifest: WatchTransferManifest) throws {
        let temporary = durableDirectory.appendingPathComponent(".\(manifest.sourceID.uuidString)-\(manifest.sequence).repair.tmp")
        try? fileManager.removeItem(at: temporary)
        try fileManager.copyItem(at: source, to: temporary)
        do {
            try validate(fileURL: temporary, manifest: manifest)
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func safeFileName(for manifest: WatchTransferManifest) -> String {
        "\(manifest.sourceID.uuidString)-\(manifest.sequence).m4a"
    }

    private func manifestURL(for manifest: WatchTransferManifest) -> URL {
        manifestURL(sourceID: manifest.sourceID, sequence: manifest.sequence)
    }

    private func manifestURL(sourceID: UUID, sequence: Int) -> URL {
        durableDirectory.appendingPathComponent("\(sourceID.uuidString)-\(sequence).json")
    }
}

final class WatchTransferReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchTransferReceiver()

    private let logger = Logger(subsystem: "com.shepswork.noted", category: "WatchConnectivity")
    private let store: WatchTransferStore

    private override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Noted/WatchTransfers", isDirectory: true)
        store = WatchTransferStore(durableDirectory: directory)
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            logger.info("WatchConnectivity is not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func pendingTransfers() -> [(manifest: WatchTransferManifest, fileURL: URL)] {
        store.pendingTransfers()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            logger.error("Activation failed: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.info("WatchConnectivity activated: \(String(describing: activationState), privacy: .public)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        logger.info("WatchConnectivity became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        logger.info("WatchConnectivity deactivated")
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        do {
            let manifest = try WatchCaptureProtocol.manifest(from: file.metadata)
            let result = try store.ingest(fileURL: file.fileURL, manifest: manifest)

            let ack = WatchDurableAck(
                protocolVersion: manifest.protocolVersion,
                sourceID: manifest.sourceID,
                sequence: manifest.sequence,
                sha256: manifest.sha256,
                acknowledgedAt: Date()
            )
            session.transferUserInfo(try WatchCaptureProtocol.ackUserInfo(for: ack))
            NotificationCenter.default.post(name: .notedWatchTransferReceived, object: nil)
            logger.info("Durably received Watch source \(manifest.sourceID.uuidString, privacy: .public), bytes=\(manifest.byteSize, privacy: .public), checksum=\(manifest.sha256, privacy: .public), existing=\(result.wasExisting, privacy: .public)")
        } catch {
            logger.error("Watch file ingestion failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        do {
            let request = try WatchCaptureProtocol.acknowledgementStatusRequest(from: userInfo)
            guard let ack = try store.durableAcknowledgement(for: request) else {
                logger.info("No durable Watch receipt found for status request source=\(request.sourceID.uuidString, privacy: .public)")
                return
            }
            session.transferUserInfo(try WatchCaptureProtocol.ackUserInfo(for: ack))
            logger.info("Re-acknowledged durably stored Watch source \(request.sourceID.uuidString, privacy: .public)")
        } catch WatchCaptureProtocolError.invalidStatusRequest {
            logger.error("Invalid Watch acknowledgement status request")
        } catch {
            logger.error("Could not reconcile Watch acknowledgement status: \(error.localizedDescription, privacy: .public)")
        }
    }
}
