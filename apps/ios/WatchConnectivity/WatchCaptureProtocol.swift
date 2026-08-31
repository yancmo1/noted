import Foundation
import CryptoKit

struct WatchAudioFormat: Codable, Hashable, Sendable {
    let codec: String
    let container: String
    let sampleRate: Int
    let channels: Int
    let bitrate: Int
}

struct WatchCaptureMark: Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let sourceElapsedTime: TimeInterval
}

struct WatchTransferManifest: Codable, Hashable, Sendable {
    static let currentProtocolVersion = 1

    let protocolVersion: Int
    let meetingID: UUID?
    let sourceID: UUID
    let sequence: Int
    let fileName: String
    let createdAt: Date
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let byteSize: Int64
    let sha256: String
    let format: WatchAudioFormat
    let marks: [WatchCaptureMark]
}

struct WatchDurableAck: Codable, Hashable, Sendable {
    let protocolVersion: Int
    let sourceID: UUID
    let sequence: Int
    let sha256: String
    let acknowledgedAt: Date
}

struct WatchAcknowledgementStatusRequest: Codable, Hashable, Sendable {
    let protocolVersion: Int
    let sourceID: UUID
    let sequence: Int
    let sha256: String
}

enum WatchTransferState: String, Codable, Hashable, Sendable {
    case local
    case queued
    case transferring
    case awaitingAck
    case acknowledged
    case failed
    case interrupted
}

enum WatchCaptureLifecycleState: String, Codable, Hashable, Sendable {
    case preparing
    case recording
    case stopConfirmation
    case stopping
    case finalizing
    case queuedForTransfer
    case transferring
    case awaitingDurableAck
    case transferred
    case storageWarning
    case interrupted
    case recordingFailed
    case transferFailed
}

enum WatchCaptureProtocol {
    static let fileKind = "noted.watch.audio"
    static let ackKind = "noted.watch.durableAck"
    static let acknowledgementStatusRequestKind = "noted.watch.ackStatusRequest"

    static func fileMetadata(for manifest: WatchTransferManifest) throws -> [String: Any] {
        try validate(manifest: manifest)
        return [
            "kind": fileKind,
            "protocolVersion": manifest.protocolVersion,
            "manifest": try JSONEncoder().encode(manifest)
        ]
    }

    static func manifest(from metadata: [String: Any]?) throws -> WatchTransferManifest {
        guard let metadata,
              metadata["kind"] as? String == fileKind,
              let payload = metadata["manifest"] as? Data else {
            throw WatchCaptureProtocolError.invalidManifest
        }
        let manifest = try JSONDecoder().decode(WatchTransferManifest.self, from: payload)
        try validate(manifest: manifest)
        return manifest
    }

    static func validate(manifest: WatchTransferManifest) throws {
        guard manifest.protocolVersion == WatchTransferManifest.currentProtocolVersion,
              manifest.sequence >= 0,
              manifest.byteSize > 0,
              manifest.duration.isFinite,
              manifest.duration >= 0,
              manifest.startedAt <= manifest.endedAt,
              !manifest.fileName.isEmpty,
              manifest.format.sampleRate > 0,
              manifest.format.channels > 0,
              manifest.format.bitrate > 0,
              manifest.sha256.count == 64,
              manifest.sha256.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
            throw WatchCaptureProtocolError.invalidManifest
        }
    }

    static func ackUserInfo(for ack: WatchDurableAck) throws -> [String: Any] {
        try validate(ack: ack)
        return [
            "kind": ackKind,
            "protocolVersion": ack.protocolVersion,
            "payload": try JSONEncoder().encode(ack)
        ]
    }

    static func ack(from userInfo: [String: Any]) throws -> WatchDurableAck {
        guard userInfo["kind"] as? String == ackKind,
              let payload = userInfo["payload"] as? Data else {
            throw WatchCaptureProtocolError.invalidAcknowledgement
        }
        let ack = try JSONDecoder().decode(WatchDurableAck.self, from: payload)
        try validate(ack: ack)
        return ack
    }

    static func validate(ack: WatchDurableAck) throws {
        guard ack.protocolVersion == WatchTransferManifest.currentProtocolVersion,
              ack.sequence >= 0,
              isValidChecksum(ack.sha256) else {
            throw WatchCaptureProtocolError.invalidAcknowledgement
        }
    }

    static func acknowledgementStatusRequestUserInfo(for request: WatchAcknowledgementStatusRequest) throws -> [String: Any] {
        try validate(statusRequest: request)
        return [
            "kind": acknowledgementStatusRequestKind,
            "protocolVersion": request.protocolVersion,
            "payload": try JSONEncoder().encode(request)
        ]
    }

    static func acknowledgementStatusRequest(from userInfo: [String: Any]) throws -> WatchAcknowledgementStatusRequest {
        guard userInfo["kind"] as? String == acknowledgementStatusRequestKind,
              let payload = userInfo["payload"] as? Data else {
            throw WatchCaptureProtocolError.invalidStatusRequest
        }
        let request = try JSONDecoder().decode(WatchAcknowledgementStatusRequest.self, from: payload)
        try validate(statusRequest: request)
        return request
    }

    static func validate(statusRequest: WatchAcknowledgementStatusRequest) throws {
        guard statusRequest.protocolVersion == WatchTransferManifest.currentProtocolVersion,
              statusRequest.sequence >= 0,
              isValidChecksum(statusRequest.sha256) else {
            throw WatchCaptureProtocolError.invalidStatusRequest
        }
    }

    static func checksum(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func byteSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else { throw WatchCaptureProtocolError.fileSizeUnavailable }
        return Int64(size)
    }

    private static func isValidChecksum(_ checksum: String) -> Bool {
        checksum.count == 64
            && checksum.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil
    }
}

enum WatchCaptureProtocolError: LocalizedError, Equatable {
    case invalidManifest
    case invalidAcknowledgement
    case invalidStatusRequest
    case fileSizeUnavailable
    case checksumMismatch
    case manifestMismatch

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "The Watch transfer did not include a valid manifest."
        case .invalidAcknowledgement: "The Watch transfer acknowledgement was invalid."
        case .invalidStatusRequest: "The Watch acknowledgement status request was invalid."
        case .fileSizeUnavailable: "The Watch recording size could not be determined."
        case .checksumMismatch: "The Watch recording checksum did not match its manifest."
        case .manifestMismatch: "The existing Watch transfer manifest did not match the retried delivery."
        }
    }
}
